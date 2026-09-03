//
//  Response.swift
//  Iris
//
//  Represents HTTP and typed network responses.
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

// MARK: - HTTPResponse

/// Represents an undecoded HTTP response.
///
/// `HTTPResponse` contains the HTTP status, raw body data, and request/response
/// metadata before a typed model has been decoded.
public struct HTTPResponse: CustomDebugStringConvertible {
    
    /// The HTTP status code of the response.
    public let statusCode: Int
    
    /// The raw response body data.
    public let data: Data
    
    /// The original URLRequest, if available.
    public let request: URLRequest?
    
    /// The HTTPURLResponse object, if available.
    public let response: HTTPURLResponse?
    
    /// Creates a new `HTTPResponse`.
    ///
    /// - Parameters:
    ///   - statusCode: The HTTP status code.
    ///   - data: The response body data.
    ///   - request: The original URL request.
    ///   - response: The HTTP URL response.
    public init(statusCode: Int, data: Data, request: URLRequest? = nil, response: HTTPURLResponse? = nil) {
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
    public func filter<R: RangeExpression>(statusCodes: R) throws -> HTTPResponse where R.Bound == Int {
        guard statusCodes.contains(statusCode) else {
            throw IrisError.statusCode(self)
        }
        return self
    }
    
    /// Returns the response if it has the specified status code.
    ///
    /// - Parameter code: The expected status code.
    /// - Returns: The response if valid.
    /// - Throws: `IrisError.statusCode` if the status code doesn't match.
    public func filter(statusCode code: Int) throws -> HTTPResponse {
        try filter(statusCodes: code...code)
    }
    
    /// Returns the response if the status code is in the 2xx range.
    ///
    /// - Returns: The response if successful.
    /// - Throws: `IrisError.statusCode` if the status code is not 2xx.
    public func filterSuccessfulStatusCodes() throws -> HTTPResponse {
        try filter(statusCodes: 200...299)
    }
    
    /// Returns the response if the status code is in the 2xx or 3xx range.
    ///
    /// - Returns: The response if successful or a redirect.
    /// - Throws: `IrisError.statusCode` if the status code is not 2xx or 3xx.
    public func filterSuccessfulStatusAndRedirectCodes() throws -> HTTPResponse {
        try filter(statusCodes: 200...399)
    }
    
    // MARK: - Mapping Methods
    
    /// Maps the response data to an image.
    ///
    /// - Returns: The decoded image.
    /// - Throws: `IrisError.imageMapping` if the data cannot be converted to an image.
    public func mapImage() throws -> Image {
        guard let image = Image(data: data) else {
            throw IrisError.imageMapping(self)
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
            throw IrisError.jsonMapping(self)
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
                throw IrisError.stringMapping(self)
            }
            return string
        } else {
            guard let string = String(data: data, encoding: .utf8) else {
                throw IrisError.stringMapping(self)
            }
            return string
        }
    }
    
    /// Maps the response data to a `Decodable` type.
    ///
    /// `Data` and `String` are treated as the raw HTTP body, not JSON:
    /// `Data` is the bytes as received, and `String` is UTF-8 text. Nested
    /// `keyPath` extraction still uses JSON; `Data` then returns the nested
    /// value's JSON bytes.
    ///
    /// - Parameters:
    ///   - type: The type to decode to.
    ///   - keyPath: Optional key path to extract the object from.
    ///   - decoder: The JSON decoder to use. Defaults to `Iris.configuration.jsonDecoder`.
    ///   - failsOnEmptyData: Whether to throw an error on empty data. Default is `true`.
    /// - Returns: The decoded object.
    /// - Throws: `IrisError.objectMapping`, `IrisError.jsonMapping`, or
    ///   `IrisError.stringMapping` if decoding fails.
    public func map<D: Decodable>(
        _ type: D.Type,
        atKeyPath keyPath: String? = nil,
        using decoder: JSONDecoder = Iris.configuration.jsonDecoder,
        failsOnEmptyData: Bool = true
    ) throws -> D {
        if D.self == Data.self {
            if let keyPath {
                guard let jsonObject = (try mapJSON(failsOnEmptyData: failsOnEmptyData) as? NSDictionary)?.value(forKeyPath: keyPath) else {
                    throw IrisError.jsonMapping(self)
                }
                do {
                    return try JSONSerialization.data(withJSONObject: jsonObject, options: [.fragmentsAllowed]) as! D
                } catch {
                    throw IrisError.jsonMapping(self)
                }
            }
            return data as! D
        }
        if D.self == String.self {
            return try mapString(atKeyPath: keyPath) as! D
        }

        let serializeToData: (Any) throws -> Data? = { jsonObject in
            guard JSONSerialization.isValidJSONObject(jsonObject) else {
                return nil
            }
            do {
                return try JSONSerialization.data(withJSONObject: jsonObject)
            } catch {
                throw IrisError.jsonMapping(self)
            }
        }
        
        let jsonData: Data
        keyPathCheck: if let keyPath = keyPath {
            guard let jsonObject = (try mapJSON(failsOnEmptyData: failsOnEmptyData) as? NSDictionary)?.value(forKeyPath: keyPath) else {
                if failsOnEmptyData {
                    throw IrisError.jsonMapping(self)
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
                    throw IrisError.jsonMapping(self)
                }
                do {
                    return try decoder.decode(DecodableWrapper<D>.self, from: wrappedJsonData).value
                } catch let error {
                    throw IrisError.objectMapping(error, self)
                }
            }
        } else {
            jsonData = data
        }
        
        do {
            if jsonData.isEmpty && !failsOnEmptyData {
                if let emptyJSONObjectData = "{}".data(using: .utf8),
                   let emptyDecodableValue = try? decoder.decode(D.self, from: emptyJSONObjectData) {
                    return emptyDecodableValue
                } else if let emptyJSONArrayData = "[{}]".data(using: .utf8),
                          let emptyDecodableValue = try? decoder.decode(D.self, from: emptyJSONArrayData) {
                    return emptyDecodableValue
                }
            }
            return try decoder.decode(D.self, from: jsonData)
        } catch let error {
            throw IrisError.objectMapping(error, self)
        }
    }
}

// MARK: - Response

/// Represents a typed network response with a decoded model.
///
/// `Response` contains a non-optional decoded model and the underlying
/// `HTTPResponse` metadata.
public struct Response<Model>: CustomDebugStringConvertible {
    
    /// The decoded model.
    public let model: Model
    
    /// The underlying HTTP response.
    public let httpResponse: HTTPResponse
    
    /// Creates a typed response from a model and an HTTP response.
    ///
    /// - Parameters:
    ///   - model: The decoded model.
    ///   - httpResponse: The underlying HTTP response.
    public init(model: Model, httpResponse: HTTPResponse) {
        self.model = model
        self.httpResponse = httpResponse
    }
    
    /// Creates a typed response from raw HTTP fields.
    ///
    /// - Parameters:
    ///   - model: The decoded model.
    ///   - statusCode: The HTTP status code.
    ///   - data: The response body data.
    ///   - request: The original URL request.
    ///   - response: The HTTP URL response.
    public init(model: Model, statusCode: Int, data: Data, request: URLRequest? = nil, response: HTTPURLResponse? = nil) {
        self.init(
            model: model,
            httpResponse: HTTPResponse(statusCode: statusCode, data: data, request: request, response: response)
        )
    }
    
    /// The HTTP status code of the response.
    public var statusCode: Int { httpResponse.statusCode }
    
    /// The raw response body data.
    public var data: Data { httpResponse.data }
    
    /// The original URLRequest, if available.
    public var request: URLRequest? { httpResponse.request }
    
    /// The HTTPURLResponse object, if available.
    public var response: HTTPURLResponse? { httpResponse.response }
    
    /// A text description of the response.
    public var description: String { httpResponse.description }
    
    /// A text description suitable for debugging.
    public var debugDescription: String { description }
    
    /// Returns the decoded model.
    public func unwrap() throws -> Model { model }
    
    /// Whether the response indicates success (status code 2xx).
    public var isSuccess: Bool { httpResponse.isSuccess }
    
    /// Whether the response is a redirect (status code 3xx).
    public var isRedirect: Bool { httpResponse.isRedirect }
    
    /// Whether the response indicates a client error (status code 4xx).
    public var isClientError: Bool { httpResponse.isClientError }
    
    /// Whether the response indicates a server error (status code 5xx).
    public var isServerError: Bool { httpResponse.isServerError }
    
    /// Returns the response if the status code falls within the specified range.
    public func filter<R: RangeExpression>(statusCodes: R) throws -> Response where R.Bound == Int {
        _ = try httpResponse.filter(statusCodes: statusCodes)
        return self
    }
    
    /// Returns the response if it has the specified status code.
    public func filter(statusCode code: Int) throws -> Response {
        _ = try httpResponse.filter(statusCode: code)
        return self
    }
    
    /// Returns the response if the status code is in the 2xx range.
    public func filterSuccessfulStatusCodes() throws -> Response {
        _ = try httpResponse.filterSuccessfulStatusCodes()
        return self
    }
    
    /// Returns the response if the status code is in the 2xx or 3xx range.
    public func filterSuccessfulStatusAndRedirectCodes() throws -> Response {
        _ = try httpResponse.filterSuccessfulStatusAndRedirectCodes()
        return self
    }
    
    /// Maps the response data to an image.
    public func mapImage() throws -> Image {
        try httpResponse.mapImage()
    }
    
    /// Maps the response data to a JSON object.
    public func mapJSON(failsOnEmptyData: Bool = true) throws -> Any {
        try httpResponse.mapJSON(failsOnEmptyData: failsOnEmptyData)
    }
    
    /// Maps the response data to a string.
    public func mapString(atKeyPath keyPath: String? = nil) throws -> String {
        try httpResponse.mapString(atKeyPath: keyPath)
    }
    
    /// Maps the response data to a `Decodable` type.
    public func map<D: Decodable>(
        _ type: D.Type,
        atKeyPath keyPath: String? = nil,
        using decoder: JSONDecoder = Iris.configuration.jsonDecoder,
        failsOnEmptyData: Bool = true
    ) throws -> D {
        try httpResponse.map(type, atKeyPath: keyPath, using: decoder, failsOnEmptyData: failsOnEmptyData)
    }
}

// MARK: - Private Helpers

/// A wrapper for decoding scalar values at key paths.
private struct DecodableWrapper<T: Decodable>: Decodable {
    let value: T
}
