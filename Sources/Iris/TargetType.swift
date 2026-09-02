//
//  TargetType.swift
//  Iris
//
//  Defines the protocol shape used by request targets.
//

import Foundation

/// The protocol used by Iris to expose request metadata to plugins and internal
/// request-building code.
///
/// `Call` is the primary public API for creating and sending requests. For
/// larger apps with multiple business domains, prefer `IrisService` plus
/// `Call` factories instead of defining Moya-style enum targets.
public protocol TargetType {

    /// The target's base `URL`.
    ///
    /// This is the root URL used when `path` is relative.
    var baseURL: URL { get }

    /// The request path.
    ///
    /// Relative paths are resolved against `baseURL`. Absolute URLs can be used
    /// directly by `Call` and do not need a base URL.
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
