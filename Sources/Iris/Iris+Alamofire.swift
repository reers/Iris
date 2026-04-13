//
//  Iris+Alamofire.swift
//  Iris
//
//  Alamofire integration and type aliases.
//  Based on Moya's Moya+Alamofire.swift.
//

import Foundation
import Alamofire

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
    
    /// Encodes an Encodable object into the request body.
    ///
    /// - Parameters:
    ///   - encodable: The object to encode.
    ///   - encoder: The JSON encoder to use. Default is a new `JSONEncoder`.
    /// - Returns: The request with the encoded body.
    /// - Throws: `IrisError.encodableMapping` if encoding fails.
    func encoded(encodable: Encodable, encoder: JSONEncoder = JSONEncoder()) throws -> URLRequest {
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
    func encoded(parameters: [String: Any], parameterEncoding: ParameterEncoding) throws -> URLRequest {
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
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    
    init(_ encodable: Encodable) {
        _encode = encodable.encode
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
public final class CancellableToken: Cancellable, CustomDebugStringConvertible {
    
    /// The action to perform when cancelled.
    let cancelAction: () -> Void
    
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
    public init(action: @escaping () -> Void) {
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

/// An interceptor that bridges the Plugin system to Alamofire.
///
/// This interceptor calls the prepare and willSend plugin methods at the
/// appropriate points in the request lifecycle.
final class IrisCallInterceptor: Alamofire.RequestInterceptor, @unchecked Sendable {
    // Note: @unchecked Sendable is safe here because:
    // 1. Properties are set once at initialization and never mutated after
    // 2. The closures are only called from Alamofire's internal synchronization
    // TODO: Consider migrating to actor-based approach in future Swift 6 migration
    
    /// Closure to prepare the request (called during adapt).
    let prepare: (@Sendable (URLRequest) -> URLRequest)?
    
    /// Closure called just before the request is sent.
    let willSend: (@Sendable (URLRequest) -> Void)?

    /// Creates a new interceptor.
    ///
    /// - Parameters:
    ///   - prepare: Closure to modify the request.
    ///   - willSend: Closure called before sending.
    init(prepare: (@Sendable (URLRequest) -> URLRequest)? = nil, willSend: (@Sendable (URLRequest) -> Void)? = nil) {
        self.prepare = prepare
        self.willSend = willSend
    }

    /// Adapts the request using the prepare closure.
    func adapt(_ urlRequest: URLRequest, for session: Alamofire.Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        let request = prepare?(urlRequest) ?? urlRequest
        willSend?(request)
        completion(.success(request))
    }
}
