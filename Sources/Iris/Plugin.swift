//
//  Plugin.swift
//  Iris
//
//  Defines the plugin system for intercepting and modifying requests and responses.
//  Based on Moya's Plugin protocol.
//

import Foundation

/// A protocol for plugins that receive callbacks to perform side effects during request lifecycle.
///
/// Plugins allow you to intercept requests at various points in their lifecycle:
/// - Before the request is sent (to modify headers, log requests, etc.)
/// - When the request is about to be sent (for tracking, showing activity indicators)
/// - After a response is received (for logging, hiding activity indicators)
/// - Before the result is returned (to transform or modify the response)
///
/// Common use cases for plugins include:
/// - Logging network requests and responses
/// - Showing/hiding network activity indicators
/// - Adding authentication tokens to requests
/// - Transforming response data
/// - Injecting errors for testing
///
/// Example:
/// ```swift
/// class LoggingPlugin: PluginType {
///     func willSend(_ request: CallType, target: TargetType) {
///         print("Sending request to: \(target.path)")
///     }
///
///     func didReceive(_ result: Result<HTTPResponse, IrisError>, target: TargetType) {
///         print("Received response for: \(target.path)")
///     }
/// }
/// ```
public protocol PluginType {
    
    /// Called to modify a request before sending.
    ///
    /// Use this method to add headers, modify the URL, or make other changes
    /// to the request before it's sent.
    ///
    /// - Parameters:
    ///   - request: The URL request that will be sent.
    ///   - target: The target type that generated this request.
    /// - Returns: The modified (or unmodified) URL request.
    func prepare(_ request: URLRequest, target: TargetType) -> URLRequest

    /// Called immediately before a request is sent over the network (or stubbed).
    ///
    /// Use this method for side effects like logging, showing activity indicators,
    /// or tracking analytics.
    ///
    /// - Parameters:
    ///   - request: The request that is about to be sent.
    ///   - target: The target type that generated this request.
    func willSend(_ request: CallType, target: TargetType)

    /// Called after a response has been received, but before Iris has invoked its completion handler.
    ///
    /// Use this method for side effects like logging, hiding activity indicators,
    /// or tracking analytics. Note that this is called before `process(_:target:)`.
    ///
    /// - Parameters:
    ///   - result: The result of the network request.
    ///   - target: The target type that generated this request.
    func didReceive(_ result: Result<HTTPResponse, IrisError>, target: TargetType)

    /// Called to modify a result before completion.
    ///
    /// Use this method to transform the response, inject errors, or modify
    /// the result before it's returned to the caller.
    ///
    /// - Parameters:
    ///   - result: The result of the network request.
    ///   - target: The target type that generated this request.
    /// - Returns: The modified (or unmodified) result.
    func process(_ result: Result<HTTPResponse, IrisError>, target: TargetType) -> Result<HTTPResponse, IrisError>
}

// MARK: - Default Implementations

public extension PluginType {
    
    /// Default implementation returns the request unchanged.
    func prepare(_ request: URLRequest, target: TargetType) -> URLRequest { request }
    
    /// Default implementation does nothing.
    func willSend(_ request: CallType, target: TargetType) { }
    
    /// Default implementation does nothing.
    func didReceive(_ result: Result<HTTPResponse, IrisError>, target: TargetType) { }
    
    /// Default implementation returns the result unchanged.
    func process(_ result: Result<HTTPResponse, IrisError>, target: TargetType) -> Result<HTTPResponse, IrisError> { result }
}

// MARK: - CallType

/// Request type used by `willSend` plugin function.
///
/// This protocol provides a way to access request information without
/// exposing Alamofire's internal types to plugins.
public protocol CallType {

    // Note:
    //
    // We use this protocol instead of the Alamofire request to avoid leaking that abstraction.
    // A plugin should not know about Alamofire at all.

    /// The underlying URL request, if available.
    var request: URLRequest? { get }

    /// Additional headers appended to the request when added to the session.
    var sessionHeaders: [String: String] { get }

    /// Authenticates the request with a username and password.
    ///
    /// - Parameters:
    ///   - username: The username for authentication.
    ///   - password: The password for authentication.
    ///   - persistence: The persistence level for the credential.
    /// - Returns: Self for chaining.
    func authenticate(username: String, password: String, persistence: URLCredential.Persistence) -> Self

    /// Authenticates the request with a credential.
    ///
    /// - Parameter credential: The credential to use for authentication.
    /// - Returns: Self for chaining.
    func authenticate(with credential: URLCredential) -> Self

    /// Returns a cURL representation of the request.
    ///
    /// This is useful for debugging purposes.
    ///
    /// - Parameter handler: A closure that receives the cURL string.
    /// - Returns: Self for chaining.
    func cURLDescription(calling handler: @escaping @Sendable (String) -> Void) -> Self
}
