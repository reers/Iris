//
//  TargetType.swift
//  Iris
//
//  Defines the protocol for describing API endpoints.
//  Based on Moya's TargetType protocol.
//

import Foundation

/// The protocol used to define the specifications necessary for a network request.
///
/// `TargetType` serves as a blueprint for API endpoints, encapsulating all the
/// information needed to construct a network request. Types conforming to this
/// protocol describe what an API endpoint looks like.
///
/// While Iris provides the `Call` struct as the primary way to build requests
/// using a chainable API, `TargetType` allows for enum-based API definitions
/// similar to Moya's approach.
///
/// Example:
/// ```swift
/// enum UserAPI: TargetType {
///     case getUser(id: Int)
///     case createUser(name: String)
///
///     var baseURL: URL { URL(string: "https://api.example.com")! }
///     var path: String {
///         switch self {
///         case .getUser(let id): return "/users/\(id)"
///         case .createUser: return "/users"
///         }
///     }
///     // ... other requirements
/// }
/// ```
public protocol TargetType {

    /// The target's base `URL`.
    ///
    /// This is the root URL for all requests made to this target.
    /// The `path` property will be appended to this URL.
    var baseURL: URL { get }

    /// The path to be appended to `baseURL` to form the full `URL`.
    ///
    /// This should not include a leading slash if `baseURL` doesn't have a trailing slash,
    /// or vice versa, to avoid double slashes in the final URL.
    var path: String { get }

    /// The HTTP method used in the request.
    ///
    /// Common values include `.get`, `.post`, `.put`, `.delete`, etc.
    var method: Method { get }

    /// Provides stub data for use in testing.
    ///
    /// When stubbing is enabled, this data will be returned instead of
    /// making an actual network request.
    ///
    /// Default is `Data()`.
    var sampleData: Data { get }

    /// The type of HTTP task to be performed.
    ///
    /// This determines how the request body and parameters are configured.
    /// See `CallTask` for available options like plain requests, uploads, downloads, etc.
    var task: CallTask { get }

    /// The type of validation to perform on the request.
    ///
    /// Validation allows automatic failure of requests that return
    /// status codes outside of expected ranges.
    ///
    /// Default is `.none`.
    var validationType: ValidationType { get }

    /// The headers to be used in the request.
    ///
    /// These headers will be merged with any default headers configured
    /// in `IrisConfiguration`.
    var headers: [String: String]? { get }
}

// MARK: - Default Implementations

public extension TargetType {

    /// The type of validation to perform on the request. Default is `.none`.
    var validationType: ValidationType { .none }

    /// Provides stub data for use in testing. Default is `Data()`.
    var sampleData: Data { Data() }
}
