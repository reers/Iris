//
//  RetryPolicy.swift
//  Iris
//
//  Per-call retry policy executed by Alamofire's RequestRetrier.
//

import Alamofire
import Foundation

/// Controls how many extra attempts a request may make after a retryable failure.
///
/// `count` is extra retries, not total attempts: `3` allows the original request
/// plus three retries. Delay is computed from `interval` and `backoff` for each
/// retry. By default only idempotent methods are retried.
///
/// Example:
/// ```swift
/// Call<User>()
///     .path("/users/1")
///     .retry(count: 2, interval: 0.5, backoff: .exponential)
/// ```
public struct RetryPolicy: Sendable, Equatable {

    /// Upper bound for retry delay, in seconds.
    ///
    /// Keeps extreme or non-finite backoff parameters from parking a request
    /// forever inside Alamofire's delayed retry scheduling.
    public static let maximumDelay: TimeInterval = 60

    /// How the wait grows between retries.
    public enum Backoff: Sendable, Equatable {
        /// Wait `interval` before every retry.
        case none
        /// Wait `interval * attempt` (`attempt` is 1-based).
        case linear
        /// Wait `interval * scale * pow(base, attempt - 1)`.
        case exponential(base: Double, scale: Double)

        /// Exponential backoff with `base` 2 and `scale` 1.
        public static let exponential = Backoff.exponential(base: 2, scale: 1)
    }

    /// Extra retries after the first attempt. `0` disables retry.
    public var count: Int

    /// Base delay in seconds before the first retry.
    public var interval: TimeInterval

    /// How the delay grows across retries.
    public var backoff: Backoff

    /// When `true`, POST / PATCH / CONNECT and other non-idempotent methods are not retried.
    public var idempotentOnly: Bool

    /// HTTP methods that may be retried when `idempotentOnly` is `true`.
    public var retryableMethods: Set<HTTPMethod>

    /// Status codes that trigger a retry when Alamofire surfaces them as errors.
    public var retryableStatusCodes: Set<Int>

    /// `URLError` codes that trigger a retry.
    public var retryableURLErrorCodes: Set<URLError.Code>

    /// GET, HEAD, PUT, DELETE, OPTIONS, and TRACE.
    public static let defaultRetryableHTTPMethods: Set<HTTPMethod> = [
        .delete, .get, .head, .options, .put, .trace
    ]

    /// 408, 429, and 500...504.
    public static let defaultRetryableHTTPStatusCodes: Set<Int> = [
        408, 429, 500, 501, 502, 503, 504
    ]

    /// Transport failures that are usually safe to retry.
    public static let defaultRetryableURLErrorCodes: Set<URLError.Code> = [
        .backgroundSessionInUseByAnotherProcess,
        .backgroundSessionWasDisconnected,
        .badServerResponse,
        .callIsActive,
        .cannotConnectToHost,
        .cannotFindHost,
        .cannotLoadFromNetwork,
        .dataNotAllowed,
        .dnsLookupFailed,
        .downloadDecodingFailedMidStream,
        .downloadDecodingFailedToComplete,
        .internationalRoamingOff,
        .networkConnectionLost,
        .notConnectedToInternet,
        .secureConnectionFailed,
        .serverCertificateHasBadDate,
        .serverCertificateNotYetValid,
        .timedOut
    ]

    /// Creates a retry policy.
    ///
    /// - Parameters:
    ///   - count: Extra retries after the first attempt.
    ///   - interval: Base delay in seconds. Default is `0.5`.
    ///   - backoff: Delay growth. Default is exponential.
    ///   - idempotentOnly: Restrict retries to idempotent methods. Default is `true`.
    ///   - retryableMethods: Methods retried when `idempotentOnly` is `true`.
    ///   - retryableStatusCodes: HTTP status codes that may be retried.
    ///   - retryableURLErrorCodes: Transport errors that may be retried.
    public init(
        count: Int,
        interval: TimeInterval = 0.5,
        backoff: Backoff = .exponential,
        idempotentOnly: Bool = true,
        retryableMethods: Set<HTTPMethod> = RetryPolicy.defaultRetryableHTTPMethods,
        retryableStatusCodes: Set<Int> = RetryPolicy.defaultRetryableHTTPStatusCodes,
        retryableURLErrorCodes: Set<URLError.Code> = RetryPolicy.defaultRetryableURLErrorCodes
    ) {
        self.count = count
        self.interval = interval
        self.backoff = backoff
        self.idempotentOnly = idempotentOnly
        self.retryableMethods = retryableMethods
        self.retryableStatusCodes = retryableStatusCodes
        self.retryableURLErrorCodes = retryableURLErrorCodes
    }

    /// Delay before the given retry. `attempt` is 1-based (`1` is the first retry).
    public func delay(beforeRetry attempt: Int) -> TimeInterval {
        let safeAttempt = max(attempt, 1)
        let delay: TimeInterval
        switch backoff {
        case .none:
            delay = interval
        case .linear:
            delay = interval * Double(safeAttempt)
        case .exponential(let base, let scale):
            delay = interval * scale * pow(base, Double(safeAttempt - 1))
        }

        if delay == .infinity {
            return Self.maximumDelay
        }
        guard delay.isFinite, delay > 0 else {
            return 0
        }
        return min(delay, Self.maximumDelay)
    }

    /// Whether this failure is eligible for another attempt.
    func shouldRetry(method: HTTPMethod?, statusCode: Int?, error: Error) -> Bool {
        if idempotentOnly {
            guard let method, retryableMethods.contains(method) else {
                return false
            }
        }

        if let statusCode, retryableStatusCodes.contains(statusCode) {
            return true
        }

        if let urlError = Self.urlError(from: error), retryableURLErrorCodes.contains(urlError.code) {
            return true
        }

        return false
    }

    /// Status codes Alamofire should treat as acceptable so retryable codes become errors.
    ///
    /// `nil` means no Alamofire status validation (every code is accepted).
    static func acceptableStatusCodes(for validation: ValidationType, policy: RetryPolicy?) -> [Int]? {
        let userCodes = validation.statusCodes
        guard let policy else {
            return userCodes.isEmpty ? nil : userCodes
        }

        let acceptable: Set<Int>
        if userCodes.isEmpty {
            acceptable = Set(100...599).subtracting(policy.retryableStatusCodes)
        } else {
            acceptable = Set(userCodes).subtracting(policy.retryableStatusCodes)
        }
        return acceptable.isEmpty ? [-1] : Array(acceptable).sorted()
    }

    /// Restores the caller's validation after retries are exhausted.
    ///
    /// Retry may internally reject 5xx so Alamofire will retry. If the user did
    /// not ask to validate those codes, the last attempt is still a success.
    static func restoreUserAcceptedStatus(
        _ delivery: NetworkDelivery,
        validation: ValidationType
    ) -> NetworkDelivery {
        guard case .failure(.statusCode(let response)) = delivery.result else {
            return delivery
        }
        let userCodes = validation.statusCodes
        guard userCodes.isEmpty || userCodes.contains(response.statusCode) else {
            return delivery
        }
        return NetworkDelivery(result: .success(response), metrics: delivery.metrics)
    }

    private static func urlError(from error: Error) -> URLError? {
        if let urlError = error as? URLError {
            return urlError
        }
        if let urlError = error.asAFError?.underlyingError as? URLError {
            return urlError
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return URLError(URLError.Code(rawValue: nsError.code))
        }
        return nil
    }
}
