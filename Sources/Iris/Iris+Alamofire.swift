//
//  Iris+Alamofire.swift
//  Iris
//
//  Alamofire integration and type aliases.
//  Based on Moya's Moya+Alamofire.swift.
//

import Foundation
import os.lock
@_exported import Alamofire

// MARK: - Public Type Aliases

/// The Alamofire session type.
public typealias Session = Alamofire.Session

/// Represents an HTTP method.
public typealias Method = Alamofire.HTTPMethod

/// Alternative name for HTTP method (for compatibility).
public typealias HTTPMethod = Alamofire.HTTPMethod

/// Choice of parameter encoding.
public typealias ParameterEncoding = Alamofire.ParameterEncoding

/// JSON parameter encoding.
public typealias JSONEncoding = Alamofire.JSONEncoding

/// URL parameter encoding.
public typealias URLEncoding = Alamofire.URLEncoding

/// Multipart form data type from Alamofire.
public typealias RequestMultipartFormData = Alamofire.MultipartFormData

/// Download destination closure type.
public typealias DownloadDestination = Alamofire.DownloadRequest.Destination

/// Request parameters dictionary. Matches Alamofire so values can cross isolation domains.
public typealias Parameters = Alamofire.Parameters

/// Request interceptor type.
public typealias RequestInterceptor = Alamofire.RequestInterceptor

// MARK: - Internal Type Aliases

internal typealias AFRequest = Alamofire.Request
internal typealias AFDownloadRequest = Alamofire.DownloadRequest
internal typealias AFUploadRequest = Alamofire.UploadRequest
internal typealias AFDataRequest = Alamofire.DataRequest
internal typealias URLRequestConvertible = Alamofire.URLRequestConvertible

// MARK: - AFRequest + CallType

/// Makes Alamofire's Request conform to our CallType protocol.
///
/// This allows plugins to work with Alamofire requests without directly
/// depending on Alamofire types.
extension AFRequest: CallType {
    // Note: AFRequest already has a `request` property
    
    /// Additional headers from the session configuration.
    public var sessionHeaders: [String: String] {
        delegate?.sessionConfiguration.httpAdditionalHeaders as? [String: String] ?? [:]
    }
}

// MARK: - URLRequest Encoding Extensions

internal extension URLRequest {

    /// Returns a cURL command that recreates this request.
    func irisCURLDescription() -> String {
        var components = ["$ curl"]

        if let method = httpMethod, method.uppercased() != "GET" {
            components.append("-X \(method.uppercased())")
        }

        let headers = (allHTTPHeaderFields ?? [:]).sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        for (name, value) in headers {
            components.append("-H \(Self.shellEscaped("\(name): \(value)"))")
        }

        if let body = httpBody, !body.isEmpty, let bodyString = String(data: body, encoding: .utf8) {
            components.append("--data \(Self.shellEscaped(bodyString))")
        }

        if let urlString = url?.absoluteString {
            components.append(Self.shellEscaped(urlString))
        }

        return components.joined(separator: " ")
    }

    private static func shellEscaped(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    /// Encodes an Encodable object into the request body.
    ///
    /// - Parameters:
    ///   - encodable: The object to encode.
    ///   - encoder: The JSON encoder to use. Defaults to `Iris.configuration.jsonEncoder`.
    /// - Returns: The request with the encoded body.
    /// - Throws: `IrisError.encodableMapping` if encoding fails.
    func encoded(encodable: any Encodable & Sendable, encoder: JSONEncoder = Iris.configuration.jsonEncoder) throws -> URLRequest {
        do {
            let encodableWrapper = AnyEncodable(encodable)
            let data = try encoder.encode(encodableWrapper)
            var request = self
            request.httpBody = data
            
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            
            return request
        } catch {
            throw IrisError.encodableMapping(error)
        }
    }
    
    /// Encodes parameters into the request using the specified encoding.
    ///
    /// - Parameters:
    ///   - parameters: The parameters to encode.
    ///   - parameterEncoding: The encoding strategy.
    /// - Returns: The request with encoded parameters.
    /// - Throws: `IrisError.parameterEncoding` if encoding fails.
    func encoded(parameters: Parameters, parameterEncoding: any ParameterEncoding) throws -> URLRequest {
        do {
            return try parameterEncoding.encode(self, with: parameters)
        } catch {
            throw IrisError.parameterEncoding(error)
        }
    }
}

// MARK: - AnyEncodable

/// Type-erased wrapper for Encodable types.
///
/// This allows encoding any Encodable value without knowing its concrete type.
private struct AnyEncodable: Encodable, Sendable {
    private let _encode: @Sendable (Encoder) throws -> Void
    
    init(_ encodable: any Encodable & Sendable) {
        _encode = { encoder in
            try encodable.encode(to: encoder)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

// MARK: - CancellableToken

/// A token that can be used to cancel requests.
///
/// `CancellableToken` wraps either a custom cancel action or an Alamofire request,
/// providing a unified interface for cancellation.
public final class CancellableToken: Cancellable, CustomDebugStringConvertible, @unchecked Sendable {
    
    /// The action to perform when cancelled.
    let cancelAction: @Sendable () -> Void
    
    /// The associated Alamofire request, if any.
    let afRequest: AFRequest?

    /// Whether this token has been cancelled.
    public fileprivate(set) var isCancelled = false

    /// Lock for thread-safe cancellation.
    fileprivate var lock: DispatchSemaphore = DispatchSemaphore(value: 1)

    /// Cancels the associated request.
    ///
    /// This method is thread-safe and will only execute the cancel action once,
    /// even if called multiple times.
    public func cancel() {
        _ = lock.wait(timeout: DispatchTime.distantFuture)
        defer { lock.signal() }
        guard !isCancelled else { return }
        isCancelled = true
        cancelAction()
    }

    /// Creates a token with a custom cancel action.
    ///
    /// - Parameter action: The action to perform when cancelled.
    public init(action: @escaping @Sendable () -> Void) {
        self.cancelAction = action
        self.afRequest = nil
    }

    /// Creates a token wrapping an Alamofire request.
    ///
    /// - Parameter request: The Alamofire request to wrap.
    init(request: AFRequest) {
        self.afRequest = request
        self.cancelAction = {
            request.cancel()
        }
    }

    /// A textual representation suitable for debugging.
    public var debugDescription: String {
        guard let request = self.afRequest else {
            return "Empty Request"
        }
        return request.cURLDescription()
    }
}

// MARK: - IrisCallInterceptor

/// Lock-protected `willSend` hook attached after the Alamofire request exists.
///
/// `@unchecked Sendable` is valid because `handler` is only read or written
/// while `lock` is held.
final class WillSendHook: @unchecked Sendable {
    private let lock: os_unfair_lock_t
    private var handler: (@Sendable (URLRequest) -> Void)?

    init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock_s())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    func set(_ handler: @escaping @Sendable (URLRequest) -> Void) {
        os_unfair_lock_lock(lock)
        self.handler = handler
        os_unfair_lock_unlock(lock)
    }

    func call(_ request: URLRequest) {
        os_unfair_lock_lock(lock)
        let handler = self.handler
        os_unfair_lock_unlock(lock)
        handler?(request)
    }
}

/// An interceptor that bridges the Plugin system to Alamofire.
///
/// This interceptor calls the prepare and willSend plugin methods at the
/// appropriate points in the request lifecycle. It is `Sendable` because both
/// stored properties are immutable and themselves `Sendable`.
final class IrisCallInterceptor: Alamofire.RequestInterceptor, Sendable {
    
    /// Closure to prepare the request (called during adapt).
    let prepare: (@Sendable (URLRequest) -> URLRequest)?
    
    /// Hook invoked just before the request is sent. Assigned after the
    /// Alamofire request exists so plugins can wrap the live request.
    let willSendHook: WillSendHook

    /// Creates a new interceptor.
    ///
    /// - Parameters:
    ///   - prepare: Closure to modify the request.
    ///   - willSendHook: Hook called before sending.
    init(
        prepare: (@Sendable (URLRequest) -> URLRequest)? = nil,
        willSendHook: WillSendHook = WillSendHook()
    ) {
        self.prepare = prepare
        self.willSendHook = willSendHook
    }

    /// Adapts the request using the prepare closure.
    func adapt(
        _ urlRequest: URLRequest,
        for session: Alamofire.Session,
        completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void
    ) {
        let request = prepare?(urlRequest) ?? urlRequest
        willSendHook.call(request)
        completion(.success(request))
    }
}
