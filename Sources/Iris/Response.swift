//
//  Response.swift
//  Iris
//
//  Represents a network response with generic model support.
//  Based on Moya's Response class with enhanced type safety.
//

import Foundation
#if canImport(UIKit)
import UIKit
/// Platform-specific image type alias.
public typealias Image = UIImage
#elseif canImport(AppKit)
import AppKit
/// Platform-specific image type alias.
public typealias Image = NSImage
#endif

// MARK: - Response

/// Represents a network response with an optional decoded model.
///
/// `Response` is a generic struct that contains both the raw response data
/// and an optionally decoded model. This allows access to both the parsed
/// result and the original response metadata.
///
/// The model is optional because:
/// - In plugin scenarios, the model may not be decoded yet
/// - Some responses may not have a body to decode
/// - The decoding might intentionally be deferred
///
/// Example:
/// ```swift
/// let response = try await Call<User>.getUser(id: 1).fire()
///
/// // Access the decoded model
/// if let user = response.model {
///     print(user.name)
/// }
///
/// // Or use unwrap() for a non-optional result
/// let user = try response.unwrap()
///
/// // Access response metadata
/// print("Status: \(response.statusCode)")
/// print("Success: \(response.isSuccess)")
/// ```
public struct Response<Model>: CustomDebugStringConvertible {
    
    /// The decoded model (may be nil in plugin scenarios).
    ///
    /// When using `fire()`, this will contain the decoded model on success.
    /// When using the response in plugins or before decoding, this may be nil.
    public let model: Model?
    
    /// The HTTP status code of the response.
    public let statusCode: Int

    /// The raw response data.
    public let data: Data

    /// The original URLRequest, if available.
    public let request: URLRequest?

    /// The HTTPURLResponse object, if available.
    public let response: HTTPURLResponse?

    /// Creates a new `Response`.
    ///
    /// - Parameters:
    ///   - model: The decoded model (optional).
    ///   - statusCode: The HTTP status code.
    ///   - data: The response body data.
    ///   - request: The original URL request.
    ///   - response: The HTTP URL response.
    public init(model: Model? = nil, statusCode: Int, data: Data, request: URLRequest? = nil, response: HTTPURLResponse? = nil) {
        self.model = model
        self.statusCode = statusCode
        self.data = data
        self.request = request
        self.response = response
    }

    /// A text description of the response.
    public var description: String {
        "Status Code: \(statusCode), Data Length: \(data.count)"
    }

    /// A text description suitable for debugging.
    public var debugDescription: String { description }
    
    // MARK: - Model Access
    
    /// Returns the model, throwing an error if it's nil.
    ///
    /// Use this method when you need a non-optional model and want to
    /// handle the nil case as an error.
    ///
    /// - Returns: The decoded model.
    /// - Throws: `IrisError.objectMapping` if the model is nil.
    public func unwrap() throws -> Model {
        guard let model else {
            throw IrisError.objectMapping(
                NSError(domain: "Iris", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model is nil"]),
                asRaw()
            )
        }
        return model
    }
    
    // MARK: - Convenience Properties
    
    /// Whether the response indicates success (status code 2xx).
    public var isSuccess: Bool {
        (200..<300).contains(statusCode)
    }
    
    /// Whether the response is a redirect (status code 3xx).
    public var isRedirect: Bool {
        (300..<400).contains(statusCode)
    }
    
    /// Whether the response indicates a client error (status code 4xx).
    public var isClientError: Bool {
        (400..<500).contains(statusCode)
    }
    
    /// Whether the response indicates a server error (status code 5xx).
    public var isServerError: Bool {
        (500..<600).contains(statusCode)
    }
    
    // MARK: - Filtering Methods

    /// Returns the response if the status code falls within the specified range.
    ///
    /// - Parameter statusCodes: The range of acceptable status codes.
    /// - Returns: The response if valid.
    /// - Throws: `IrisError.statusCode` if the status code is outside the range.
    public func filter<R: RangeExpression>(statusCodes: R) throws -> Response where R.Bound == Int {
        guard statusCodes.contains(statusCode) else {
            throw IrisError.statusCode(asRaw())
        }
        return self
    }

    /// Returns the response if it has the specified status code.
    ///
    /// - Parameter code: The expected status code.
    /// - Returns: The response if valid.
    /// - Throws: `IrisError.statusCode` if the status code doesn't match.
    public func filter(statusCode code: Int) throws -> Response {
        try filter(statusCodes: code...code)
    }

    /// Returns the response if the status code is in the 2xx range.
    ///
    /// - Returns: The response if successful.
    /// - Throws: `IrisError.statusCode` if the status code is not 2xx.
    public func filterSuccessfulStatusCodes() throws -> Response {
        try filter(statusCodes: 200...299)
    }

    /// Returns the response if the status code is in the 2xx or 3xx range.
    ///
    /// - Returns: The response if successful or a redirect.
    /// - Throws: `IrisError.statusCode` if the status code is not 2xx or 3xx.
    public func filterSuccessfulStatusAndRedirectCodes() throws -> Response {
        try filter(statusCodes: 200...399)
    }

    // MARK: - Mapping Methods

    /// Maps the response data to an image.
    ///
    /// - Returns: The decoded image.
    /// - Throws: `IrisError.imageMapping` if the data cannot be converted to an image.
    public func mapImage() throws -> Image {
        guard let image = Image(data: data) else {
            throw IrisError.imageMapping(asRaw())
        }
        return image
    }

    /// Maps the response data to a JSON object.
    ///
    /// - Parameter failsOnEmptyData: Whether to throw an error on empty data. Default is `true`.
    /// - Returns: The parsed JSON object.
    /// - Throws: `IrisError.jsonMapping` if parsing fails.
    public func mapJSON(failsOnEmptyData: Bool = true) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        } catch {
            if data.isEmpty && !failsOnEmptyData {
                return NSNull()
            }
            throw IrisError.jsonMapping(asRaw())
        }
    }

    /// Maps the response data to a string.
    ///
    /// - Parameter keyPath: Optional key path to extract the string from JSON.
    /// - Returns: The string value.
    /// - Throws: `IrisError.stringMapping` if the data cannot be converted to a string.
    public func mapString(atKeyPath keyPath: String? = nil) throws -> String {
        if let keyPath = keyPath {
            guard let jsonDictionary = try mapJSON() as? NSDictionary,
                let string = jsonDictionary.value(forKeyPath: keyPath) as? String else {
                    throw IrisError.stringMapping(asRaw())
            }
            return string
        } else {
            guard let string = String(data: data, encoding: .utf8) else {
                throw IrisError.stringMapping(asRaw())
            }
            return string
        }
    }

    /// Maps the response data to a `Decodable` type.
    ///
    /// This method supports extracting nested objects using key paths.
    ///
    /// - Parameters:
    ///   - type: The type to decode to.
    ///   - keyPath: Optional key path to extract the object from.
    ///   - decoder: The JSON decoder to use. Default is a new `JSONDecoder`.
    ///   - failsOnEmptyData: Whether to throw an error on empty data. Default is `true`.
    /// - Returns: The decoded object.
    /// - Throws: `IrisError.objectMapping` or `IrisError.jsonMapping` if decoding fails.
    public func map<D: Decodable>(_ type: D.Type, atKeyPath keyPath: String? = nil, using decoder: JSONDecoder = JSONDecoder(), failsOnEmptyData: Bool = true) throws -> D {
        let serializeToData: (Any) throws -> Data? = { (jsonObject) in
            guard JSONSerialization.isValidJSONObject(jsonObject) else {
                return nil
            }
            do {
                return try JSONSerialization.data(withJSONObject: jsonObject)
            } catch {
                throw IrisError.jsonMapping(self.asRaw())
            }
        }
        let jsonData: Data
        keyPathCheck: if let keyPath = keyPath {
            guard let jsonObject = (try mapJSON(failsOnEmptyData: failsOnEmptyData) as? NSDictionary)?.value(forKeyPath: keyPath) else {
                if failsOnEmptyData {
                    throw IrisError.jsonMapping(asRaw())
                } else {
                    jsonData = data
                    break keyPathCheck
                }
            }

            if let data = try serializeToData(jsonObject) {
                jsonData = data
            } else {
                let wrappedJsonObject = ["value": jsonObject]
                let wrappedJsonData: Data
                if let data = try serializeToData(wrappedJsonObject) {
                    wrappedJsonData = data
                } else {
                    throw IrisError.jsonMapping(asRaw())
                }
                do {
                    return try decoder.decode(DecodableWrapper<D>.self, from: wrappedJsonData).value
                } catch let error {
                    throw IrisError.objectMapping(error, asRaw())
                }
            }
        } else {
            jsonData = data
        }
        do {
            if jsonData.isEmpty && !failsOnEmptyData {
                if let emptyJSONObjectData = "{}".data(using: .utf8), let emptyDecodableValue = try? decoder.decode(D.self, from: emptyJSONObjectData) {
                    return emptyDecodableValue
                } else if let emptyJSONArrayData = "[{}]".data(using: .utf8), let emptyDecodableValue = try? decoder.decode(D.self, from: emptyJSONArrayData) {
                    return emptyDecodableValue
                }
            }
            return try decoder.decode(D.self, from: jsonData)
        } catch let error {
            throw IrisError.objectMapping(error, asRaw())
        }
    }
    
    // MARK: - Type Conversion
    
    /// Converts this response to a `RawResponse` (without model).
    ///
    /// This is useful when you need to pass the response to APIs that
    /// expect `RawResponse`, such as plugin methods.
    ///
    /// - Returns: A `RawResponse` with the same data but no model.
    public func asRaw() -> RawResponse {
        RawResponse(statusCode: statusCode, data: data, request: request, response: response)
    }
}

// MARK: - RawResponse Type Alias

/// A response without a decoded model.
///
/// `RawResponse` is used in plugin scenarios where the response data
/// hasn't been decoded yet, or when the response type doesn't matter.
///
/// It's defined as `Response<Never>` to indicate that no model is available.
public typealias RawResponse = Response<Never>

// MARK: - RawResponse Convenience

public extension Response where Model == Never {
    
    /// Creates a `RawResponse` without a model.
    ///
    /// - Parameters:
    ///   - statusCode: The HTTP status code.
    ///   - data: The response body data.
    ///   - request: The original URL request.
    ///   - response: The HTTP URL response.
    init(statusCode: Int, data: Data, request: URLRequest? = nil, response: HTTPURLResponse? = nil) {
        self.init(model: nil, statusCode: statusCode, data: data, request: request, response: response)
    }
}

// MARK: - Private Helpers

/// A wrapper for decoding scalar values at key paths.
private struct DecodableWrapper<T: Decodable>: Decodable {
    let value: T
}
