//
//  ValidationType.swift
//  Iris
//
//  Defines the validation types for HTTP status codes.
//  Based on Moya's ValidationType.
//

import Foundation

/// Represents the status codes to validate through Alamofire.
///
/// `ValidationType` allows you to specify which HTTP status codes should be
/// considered successful. Responses with status codes outside the specified
/// range will result in an `IrisError.statusCode` error.
///
/// Example:
/// ```swift
/// // Only accept 2xx responses
/// Call<User>()
///     .validate(.successCodes)
///
/// // Accept 2xx and 3xx responses
/// Call<User>()
///     .validate(.successAndRedirectCodes)
///
/// // Accept specific status codes
/// Call<User>()
///     .validate(.customCodes([200, 201, 204]))
/// ```
public enum ValidationType {

    /// No validation. All status codes are accepted.
    case none

    /// Validate success codes (only 2xx).
    ///
    /// This is the most common validation type for API requests.
    case successCodes

    /// Validate success and redirect codes (2xx and 3xx).
    ///
    /// Use this when your API might return redirects that should be handled.
    case successAndRedirectCodes

    /// Validate only the given status codes.
    ///
    /// Use this for APIs with non-standard success codes.
    ///
    /// - Parameter codes: The list of acceptable status codes.
    case customCodes([Int])

    /// The list of HTTP status codes to validate.
    ///
    /// Returns an empty array for `.none`, allowing all status codes.
    public var statusCodes: [Int] {
        switch self {
        case .successCodes:
            return Array(200..<300)
        case .successAndRedirectCodes:
            return Array(200..<400)
        case .customCodes(let codes):
            return codes
        case .none:
            return []
        }
    }
}

// MARK: - Equatable

extension ValidationType: Equatable {

    /// Compares two validation types for equality.
    public static func == (lhs: ValidationType, rhs: ValidationType) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none),
             (.successCodes, .successCodes),
             (.successAndRedirectCodes, .successAndRedirectCodes):
            return true
        case (.customCodes(let code1), .customCodes(let code2)):
            return code1 == code2
        default:
            return false
        }
    }
}
