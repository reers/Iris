//
//  IrisError.swift
//  Iris
//
//  Defines the error types that Iris can throw.
//  Based on Moya's MoyaError.
//

import Foundation

/// A type representing possible errors Iris can throw.
///
/// `IrisError` provides detailed information about what went wrong during
/// a network request. Each case represents a different type of failure,
/// from response mapping issues to network-level errors.
///
/// Example:
/// ```swift
/// do {
///     let user = try await request.fetch()
/// } catch let error as IrisError {
///     switch error {
///     case .statusCode(let response):
///         print("Server returned status \(response.statusCode)")
///     case .objectMapping(let decodingError, _):
///         print("Failed to decode: \(decodingError)")
///     case .underlying(let error, _):
///         print("Network error: \(error)")
///     default:
///         print("Other error: \(error)")
///     }
/// }
/// ```
public enum IrisError: Swift.Error {

    /// Indicates a response failed to map to an image.
    ///
    /// This occurs when the response data cannot be converted to a `UIImage` or `NSImage`.
    case imageMapping(HTTPResponse)

    /// Indicates a response failed to map to a JSON structure.
    ///
    /// This occurs when `JSONSerialization` fails to parse the response data.
    case jsonMapping(HTTPResponse)

    /// Indicates a response failed to map to a String.
    ///
    /// This occurs when the response data cannot be converted to a UTF-8 string.
    case stringMapping(HTTPResponse)

    /// Indicates a response failed to map to a Decodable object.
    ///
    /// The associated `Error` contains the underlying decoding error with details
    /// about what went wrong during `Decodable` conformance.
    case objectMapping(Swift.Error, HTTPResponse)

    /// Indicates that an Encodable object couldn't be encoded into Data.
    ///
    /// This occurs when `JSONEncoder` fails to encode the request body.
    case encodableMapping(Swift.Error)

    /// Indicates a response failed with an invalid HTTP status code.
    ///
    /// This error is thrown when validation is enabled and the response status code
    /// falls outside the acceptable range.
    case statusCode(HTTPResponse)

    /// Indicates a response failed due to an underlying error.
    ///
    /// This wraps errors from the underlying networking layer (Alamofire/URLSession).
    /// The response may be nil if the error occurred before receiving a response.
    case underlying(Swift.Error, HTTPResponse?)

    /// Indicates that an `Endpoint` failed to map to a `URLRequest`.
    ///
    /// This typically occurs when the URL string is malformed.
    case requestMapping(String)

    /// Indicates that an `Endpoint` failed to encode the parameters for the `URLRequest`.
    ///
    /// This wraps parameter encoding errors from Alamofire.
    case parameterEncoding(Swift.Error)
}

// MARK: - Response Property

public extension IrisError {
    
    /// The associated response object, if available.
    ///
    /// This allows access to the response data even when an error occurred,
    /// which can be useful for debugging or extracting error messages from the server.
    var response: HTTPResponse? {
        switch self {
        case .imageMapping(let response): return response
        case .jsonMapping(let response): return response
        case .stringMapping(let response): return response
        case .objectMapping(_, let response): return response
        case .encodableMapping: return nil
        case .statusCode(let response): return response
        case .underlying(_, let response): return response
        case .requestMapping: return nil
        case .parameterEncoding: return nil
        }
    }

    /// The underlying error, if available.
    ///
    /// For errors that wrap another error (like `objectMapping` or `underlying`),
    /// this property provides access to the original error for detailed debugging.
    var underlyingError: Swift.Error? {
        switch self {
        case .imageMapping: return nil
        case .jsonMapping: return nil
        case .stringMapping: return nil
        case .objectMapping(let error, _): return error
        case .encodableMapping(let error): return error
        case .statusCode: return nil
        case .underlying(let error, _): return error
        case .requestMapping: return nil
        case .parameterEncoding(let error): return error
        }
    }
}

// MARK: - Error Descriptions

extension IrisError: LocalizedError {
    
    /// A human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .imageMapping:
            return "Failed to map data to an Image."
        case .jsonMapping:
            return "Failed to map data to JSON."
        case .stringMapping:
            return "Failed to map data to a String."
        case .objectMapping:
            return "Failed to map data to a Decodable object."
        case .encodableMapping:
            return "Failed to encode Encodable object into data."
        case .statusCode:
            return "Status code didn't fall within the given range."
        case .underlying(let error, _):
            return error.localizedDescription
        case .requestMapping:
            return "Failed to map Endpoint to a URLRequest."
        case .parameterEncoding(let error):
            return "Failed to encode parameters for URLRequest. \(error.localizedDescription)"
        }
    }
}

// MARK: - Error User Info

extension IrisError: CustomNSError {
    
    /// User info dictionary for NSError bridging.
    public var errorUserInfo: [String: Any] {
        var userInfo: [String: Any] = [:]
        userInfo[NSLocalizedDescriptionKey] = errorDescription
        userInfo[NSUnderlyingErrorKey] = underlyingError
        return userInfo
    }
}
