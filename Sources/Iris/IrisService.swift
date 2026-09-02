//
//  IrisService.swift
//  Iris
//
//  Service-scoped defaults for groups of related requests.
//

import Foundation

/// A service-scoped request factory.
///
/// Use `IrisService` when a group of endpoints share defaults such as a
/// `baseURL`, headers, or timeout that should sit between global configuration
/// and per-request overrides.
public struct IrisService {
    
    /// The base URL used by calls created from this service.
    public var baseURL: URL?
    
    /// Default headers used by calls created from this service.
    public var headers: [String: String]
    
    /// The default timeout used by calls created from this service.
    public var timeout: TimeInterval?
    
    /// Creates a service with optional scoped defaults.
    ///
    /// - Parameters:
    ///   - baseURL: The service base URL.
    ///   - headers: Headers applied after global headers and before request headers.
    ///   - timeout: Timeout applied after global timeout and before request timeout.
    public init(
        baseURL: URL? = nil,
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) {
        self.baseURL = baseURL
        self.headers = headers
        self.timeout = timeout
    }
    
    /// Creates a service with a base URL string.
    ///
    /// - Parameters:
    ///   - baseURL: The service base URL string.
    ///   - headers: Headers applied after global headers and before request headers.
    ///   - timeout: Timeout applied after global timeout and before request timeout.
    public init(
        baseURL: String,
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) {
        self.init(baseURL: URL(string: baseURL), headers: headers, timeout: timeout)
    }
    
    /// Creates a `Call` scoped to this service.
    ///
    /// - Parameter type: The expected decoded response type.
    /// - Returns: A call using this service's defaults.
    public func call<Model: Decodable>(_ type: Model.Type = Model.self) -> Call<Model> {
        var request = Call<Model>()
        request.service = self
        return request
    }
}
