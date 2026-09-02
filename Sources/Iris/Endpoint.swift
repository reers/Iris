//
//  Endpoint.swift
//  Iris
//
//  Represents a concrete endpoint that can be converted to a URLRequest.
//  Based on Moya's Endpoint class.
//

import Foundation

/// Represents the sample response for stubbing.
///
/// Use these cases to define what should be returned when stubbing
/// a network request for testing purposes.
public enum EndpointSampleResponse {

    /// The network returned a response, including status code and data.
    ///
    /// - Parameters:
    ///   - statusCode: The HTTP status code (e.g., 200, 404).
    ///   - data: The response body data.
    case networkResponse(Int, Data)

    /// The network returned a fully customized response.
    ///
    /// Use this when you need full control over the HTTP response object.
    ///
    /// - Parameters:
    ///   - response: The HTTPURLResponse object.
    ///   - data: The response body data.
    case response(HTTPURLResponse, Data)

    /// The network failed to send the request, or failed to retrieve a response.
    ///
    /// Use this to simulate network errors like timeouts or connectivity issues.
    ///
    /// - Parameter error: The error that occurred.
    case networkError(NSError)
}

/// Class for reifying a target into a concrete endpoint.
///
/// An `Endpoint` represents a concrete network request with all its parameters
/// resolved. It serves as an intermediate representation between a `TargetType`
/// and a `URLRequest`.
///
/// Endpoints can be customized before being converted to URL requests,
/// allowing for modifications like adding headers or changing the task.
open class Endpoint {
    
    /// A closure type that returns an `EndpointSampleResponse`.
    public typealias SampleResponseClosure = () -> EndpointSampleResponse

    /// A string representation of the URL for the request.
    public let url: String

    /// A closure responsible for returning an `EndpointSampleResponse`.
    ///
    /// This is used when stubbing to provide test data.
    public let sampleResponseClosure: SampleResponseClosure

    /// The HTTP method for the request.
    public let method: Method

    /// The `CallTask` for the request.
    ///
    /// This defines how the request body and parameters are configured.
    public let task: CallTask

    /// The HTTP header fields for the request.
    public let httpHeaderFields: [String: String]?

    /// Creates a new `Endpoint`.
    ///
    /// - Parameters:
    ///   - url: The URL string for the request.
    ///   - sampleResponseClosure: A closure returning sample data for stubbing.
    ///   - method: The HTTP method.
    ///   - task: The task type defining request body/parameters.
    ///   - httpHeaderFields: Optional HTTP headers.
    public init(url: String,
                sampleResponseClosure: @escaping SampleResponseClosure,
                method: Method,
                task: CallTask,
                httpHeaderFields: [String: String]?) {

        self.url = url
        self.sampleResponseClosure = sampleResponseClosure
        self.method = method
        self.task = task
        self.httpHeaderFields = httpHeaderFields
    }

    /// Creates a new `Endpoint` with additional HTTP header fields.
    ///
    /// This is a convenience method for adding headers while preserving
    /// all other endpoint properties.
    ///
    /// - Parameter newHTTPHeaderFields: The headers to add.
    /// - Returns: A new `Endpoint` with the added headers.
    open func adding(newHTTPHeaderFields: [String: String]) -> Endpoint {
        Endpoint(url: url, sampleResponseClosure: sampleResponseClosure, method: method, task: task, httpHeaderFields: add(httpHeaderFields: newHTTPHeaderFields))
    }

    /// Creates a new `Endpoint` with a replaced task.
    ///
    /// This is a convenience method for changing the task while preserving
    /// all other endpoint properties.
    ///
    /// - Parameter task: The new task to use.
    /// - Returns: A new `Endpoint` with the replaced task.
    open func replacing(task: CallTask) -> Endpoint {
        Endpoint(url: url, sampleResponseClosure: sampleResponseClosure, method: method, task: task, httpHeaderFields: httpHeaderFields)
    }

    /// Merges new headers with existing headers.
    ///
    /// - Parameter headers: The headers to add.
    /// - Returns: The merged headers dictionary.
    fileprivate func add(httpHeaderFields headers: [String: String]?) -> [String: String]? {
        guard let unwrappedHeaders = headers, unwrappedHeaders.isEmpty == false else {
            return self.httpHeaderFields
        }

        var newHTTPHeaderFields = self.httpHeaderFields ?? [:]
        unwrappedHeaders.forEach { key, value in
            newHTTPHeaderFields[key] = value
        }
        return newHTTPHeaderFields
    }
}

// MARK: - URLRequest Conversion

/// Extension for converting an `Endpoint` into a `URLRequest`.
public extension Endpoint {
    
    /// Converts the endpoint to a `URLRequest`.
    ///
    /// This method handles all the different task types and properly encodes
    /// parameters into the request.
    ///
    /// - Returns: A `URLRequest` ready to be executed.
    /// - Throws: `IrisError.requestMapping` if the URL is invalid,
    ///           or other errors if encoding fails.
    func urlRequest() throws -> URLRequest {
        guard let requestURL = Foundation.URL(string: url) else {
            throw IrisError.requestMapping(url)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method.rawValue
        request.allHTTPHeaderFields = httpHeaderFields

        switch task {
        case .requestPlain, .uploadFile, .uploadMultipartFormData, .downloadDestination:
            return request
        case .requestData(let data):
            request.httpBody = data
            return request
        case let .requestJSONEncodable(encodable):
            return try request.encoded(encodable: encodable)
        case let .requestCustomJSONEncodable(encodable, encoder: encoder):
            return try request.encoded(encodable: encodable, encoder: encoder)
        case let .requestParameters(parameters, parameterEncoding):
            return try request.encoded(parameters: parameters, parameterEncoding: parameterEncoding)
        case let .uploadCompositeMultipartFormData(_, urlParameters):
            let parameterEncoding = URLEncoding(destination: .queryString)
            return try request.encoded(parameters: urlParameters, parameterEncoding: parameterEncoding)
        case let .downloadParameters(parameters, parameterEncoding, _):
            return try request.encoded(parameters: parameters, parameterEncoding: parameterEncoding)
        case let .requestCompositeData(bodyData: bodyData, urlParameters: urlParameters):
            request.httpBody = bodyData
            let parameterEncoding = URLEncoding(destination: .queryString)
            return try request.encoded(parameters: urlParameters, parameterEncoding: parameterEncoding)
        case let .requestCompositeParameters(bodyParameters: bodyParameters, bodyEncoding: bodyParameterEncoding, urlParameters: urlParameters):
            if let bodyParameterEncoding = bodyParameterEncoding as? URLEncoding, bodyParameterEncoding.destination != .httpBody {
                let error = NSError(
                    domain: "Iris.Endpoint",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Only URLEncoding.httpBody is allowed as bodyEncoding. Add URL parameters to urlParameters instead."
                    ]
                )
                throw IrisError.parameterEncoding(error)
            }
            let bodyfulRequest = try request.encoded(parameters: bodyParameters, parameterEncoding: bodyParameterEncoding)
            let urlEncoding = URLEncoding(destination: .queryString)
            return try bodyfulRequest.encoded(parameters: urlParameters, parameterEncoding: urlEncoding)
        }
    }
}

// MARK: - Equatable & Hashable

/// Extension making `Endpoint` usable as a dictionary key.
extension Endpoint: Equatable, Hashable {
    
    /// Computes the hash value for the endpoint.
    ///
    /// The hash considers both the URL request and any upload-specific data.
    public func hash(into hasher: inout Hasher) {
        switch task {
        case let .uploadFile(file):
            hasher.combine(file)
        case let .uploadMultipartFormData(multipartFormData), let .uploadCompositeMultipartFormData(multipartFormData, _):
            hasher.combine(multipartFormData)
        default:
            break
        }

        if let request = try? urlRequest() {
            hasher.combine(request)
        } else {
            hasher.combine(url)
        }
    }

    /// Compares two endpoints for equality.
    ///
    /// Note: If both endpoints fail to produce a URLRequest, the comparison
    /// falls back to comparing hash values.
    public static func == (lhs: Endpoint, rhs: Endpoint) -> Bool {
        let areEndpointsEqualInAdditionalProperties: Bool = {
            switch (lhs.task, rhs.task) {
            case (let .uploadFile(file1), let .uploadFile(file2)):
                return file1 == file2
            case (let .uploadMultipartFormData(multipartFormData1), let .uploadMultipartFormData(multipartFormData2)),
                 (let .uploadCompositeMultipartFormData(multipartFormData1, _), let .uploadCompositeMultipartFormData(multipartFormData2, _)):
                return multipartFormData1 == multipartFormData2
            default:
                return true
            }
        }()
        let lhsRequest = try? lhs.urlRequest()
        let rhsRequest = try? rhs.urlRequest()
        if lhsRequest != nil, rhsRequest == nil { return false }
        if lhsRequest == nil, rhsRequest != nil { return false }
        if lhsRequest == nil, rhsRequest == nil { return lhs.hashValue == rhs.hashValue && areEndpointsEqualInAdditionalProperties }
        return lhsRequest == rhsRequest && areEndpointsEqualInAdditionalProperties
    }
}
