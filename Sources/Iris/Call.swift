//
//  Call.swift
//  Iris
//
//  The chainable request builder - Iris's signature feature.
//  All request configuration is centralized in one place.
//

import Alamofire
import Foundation

/// A network request built using a chainable API.
///
/// `Call` is Iris's signature feature that allows you to define all aspects
/// of a network request in a single, fluent chain. This eliminates the need for
/// separate enum cases or scattered configuration.
///
/// Example:
/// ```swift
/// // Define API endpoints as static factory methods
/// extension Call {
///     static func getUser(id: Int) -> Call<User> {
///         Call<User>()
///             .path("/users/\(id)")
///             .method(.get)
///             .validateSuccessCodes()
///     }
///
///     static func createUser(name: String) -> Call<User> {
///         Call<User>()
///             .path("/users")
///             .method(.post)
///             .body(["name": name])
///             .validateSuccessCodes()
///     }
/// }
///
/// // Execute requests
/// let user = try await Call<User>.getUser(id: 123).fetch()
/// ```
public struct Call<ResponseType: Decodable>: TargetType {
    
    // MARK: - TargetType Properties
    
    /// The base URL for the request.
    ///
    /// If not set explicitly, falls back to the global configuration's baseURL.
    public var baseURL: URL {
        guard let baseURL = configuredBaseURL else {
            preconditionFailure("baseURL is required unless path is an absolute URL")
        }
        return baseURL
    }
    
    /// The path component to append to the base URL.
    public var path: String = ""
    
    /// The HTTP method for the request.
    public var method: Method = .get
    
    /// The task type defining how the request body is configured.
    public var task: CallTask = .requestPlain
    
    /// Custom HTTP headers for this request.
    public var headers: [String: String]?
    
    /// The validation type for response status codes.
    public var validationType: ValidationType = .none
    
    /// Sample data for stubbing during testing.
    public var sampleData: Data = Data()
    
    /// The sample response returned in stub mode.
    var sampleResponseClosure: Endpoint.SampleResponseClosure {
        _sampleResponseClosure ?? { .networkResponse(200, sampleData) }
    }
    
    // MARK: - Iris Extended Properties
    
    /// Custom base URL that overrides the global configuration.
    private var _baseURL: URL?
    
    /// Service-scoped defaults applied between global configuration and request overrides.
    var service: IrisService?
    
    /// Custom sample response that overrides the default 200 + sampleData stub.
    private var _sampleResponseClosure: Endpoint.SampleResponseClosure?
    
    /// The per-request or globally configured base URL, if any.
    var configuredBaseURL: URL? {
        _baseURL ?? service?.baseURL ?? Iris.configuration.baseURL
    }
    
    /// Per-request timeout that overrides the global configuration.
    private var _timeout: TimeInterval?
    
    /// Request timeout interval in seconds.
    ///
    /// Uses the per-request timeout when set, otherwise `IrisConfiguration.defaultTimeout`
    /// (which defaults to 30 seconds).
    public var timeout: TimeInterval {
        get { _timeout ?? service?.timeout ?? Iris.configuration.defaultTimeout }
        set { _timeout = newValue }
    }
    
    /// Custom JSON decoder for response parsing.
    public var decoder: JSONDecoder?
    
    /// Stub behavior that overrides the global configuration.
    public var stubBehavior: StubBehavior?
    
    /// Completion handler for processing decoded Alamofire response.
    ///
    /// This handler is called after the request completes and response is decoded,
    /// providing access to the typed response for generic processing like caching or database storage.
    public var onCompleteHandler: (@Sendable (AFDataResponse<ResponseType>) -> Void)?
    
    // MARK: - Initialization
    
    /// Creates a new empty request.
    public init() {}
    
    // MARK: - Basic Configuration (Chainable)
    
    /// Sets the request path.
    ///
    /// - Parameter path: The path to append to the base URL.
    /// - Returns: A new call with the updated path.
    public func path(_ path: String) -> Call<ResponseType> {
        var request = self
        request.path = path
        return request
    }
    
    /// Sets the HTTP method.
    ///
    /// - Parameter method: The HTTP method (GET, POST, PUT, DELETE, etc.).
    /// - Returns: A new call with the updated method.
    public func method(_ method: Method) -> Call<ResponseType> {
        var request = self
        request.method = method
        return request
    }
    
    /// Sets the request timeout interval, overriding the global configuration.
    ///
    /// - Parameter timeout: The timeout in seconds.
    /// - Returns: A new call with the updated timeout.
    public func timeout(_ timeout: TimeInterval) -> Call<ResponseType> {
        var request = self
        request._timeout = timeout
        return request
    }
    
    // MARK: - Headers Configuration
    
    /// Sets all request headers.
    ///
    /// - Parameter headers: A dictionary of header fields.
    /// - Returns: A new call with the updated headers.
    public func headers(_ headers: [String: String]) -> Call<ResponseType> {
        var request = self
        request.headers = headers
        return request
    }
    
    /// Adds a single header to the request.
    ///
    /// - Parameters:
    ///   - key: The header field name.
    ///   - value: The header field value.
    /// - Returns: A new call with the added header.
    public func header(_ key: String, _ value: String) -> Call<ResponseType> {
        var request = self
        var currentHeaders = request.headers ?? [:]
        currentHeaders[key] = value
        request.headers = currentHeaders
        return request
    }
    
    /// Adds an Authorization header.
    ///
    /// - Parameter value: The full authorization header value.
    /// - Returns: A new call with the Authorization header.
    public func authorization(_ value: String) -> Call<ResponseType> {
        header("Authorization", value)
    }
    
    /// Adds a Bearer token Authorization header.
    ///
    /// - Parameter token: The bearer token.
    /// - Returns: A new call with the Bearer Authorization header.
    public func bearerToken(_ token: String) -> Call<ResponseType> {
        header("Authorization", "Bearer \(token)")
    }
    
    // MARK: - Task Configuration
    
    /// Sets the request task type.
    ///
    /// - Parameter task: The task defining request body configuration.
    /// - Returns: A new call with the updated task.
    public func task(_ task: CallTask) -> Call<ResponseType> {
        var request = self
        request.task = task
        return request
    }
    
    /// Sets URL query parameters.
    ///
    /// - Parameter parameters: The query parameters.
    /// - Returns: A new call with URL-encoded query parameters.
    public func query(_ parameters: [String: Any]) -> Call<ResponseType> {
        var request = self
        request.task = .requestParameters(parameters: parameters, encoding: URLEncoding.queryString)
        return request
    }
    
    /// Sets the request body as a JSON dictionary.
    ///
    /// - Parameter parameters: The body parameters.
    /// - Returns: A new call with JSON-encoded body.
    public func body(_ parameters: [String: Any]) -> Call<ResponseType> {
        var request = self
        request.task = .requestParameters(parameters: parameters, encoding: JSONEncoding.default)
        return request
    }
    
    /// Sets the request body using a builder closure.
    ///
    /// This method allows you to dynamically build the JSON body using a closure
    /// that receives a mutable dictionary reference.
    ///
    /// Example:
    /// ```swift
    /// Call<User>()
    ///     .body { json in
    ///         json["name"] = "John"
    ///         if includeAge {
    ///             json["age"] = 30
    ///         }
    ///     }
    /// ```
    ///
    /// - Parameter builder: A closure that receives an `inout` dictionary to populate.
    /// - Returns: A new call with JSON-encoded body.
    public func body(_ builder: (_ json: inout [String: Any]) -> Void) -> Call<ResponseType> {
        var parameters: [String: Any] = [:]
        builder(&parameters)
        return body(parameters)
    }
    
    /// Sets the request body from an Encodable object.
    ///
    /// Encoded with `IrisConfiguration.jsonEncoder` unless `body(_:encoder:)` is used.
    ///
    /// - Parameter encodable: The object to encode as JSON.
    /// - Returns: A new call with JSON-encoded body.
    public func body<T: Encodable>(_ encodable: T) -> Call<ResponseType> {
        var request = self
        request.task = .requestJSONEncodable(encodable)
        return request
    }
    
    /// Sets the request body from an Encodable object with a custom encoder.
    ///
    /// - Parameters:
    ///   - encodable: The object to encode.
    ///   - encoder: The custom JSON encoder.
    /// - Returns: A new call with custom-encoded body.
    public func body<T: Encodable>(_ encodable: T, encoder: JSONEncoder) -> Call<ResponseType> {
        var request = self
        request.task = .requestCustomJSONEncodable(encodable, encoder: encoder)
        return request
    }
    
    /// Sets the request body as raw data.
    ///
    /// - Parameter data: The raw data to send.
    /// - Returns: A new call with raw data body.
    public func body(_ data: Data) -> Call<ResponseType> {
        var request = self
        request.task = .requestData(data)
        return request
    }
    
    /// Sets the request body as form URL-encoded data.
    ///
    /// - Parameter parameters: The form parameters.
    /// - Returns: A new call with form-encoded body.
    public func formBody(_ parameters: [String: Any]) -> Call<ResponseType> {
        var request = self
        request.task = .requestParameters(parameters: parameters, encoding: URLEncoding.httpBody)
        return request
    }
    
    /// Sets both URL query parameters and a JSON body.
    ///
    /// - Parameters:
    ///   - query: URL query parameters.
    ///   - body: Body parameters.
    ///   - bodyEncoding: The encoding for body parameters. Default is JSON.
    /// - Returns: A new call with composite parameters.
    public func composite(
        query: [String: Any],
        body: [String: Any],
        bodyEncoding: ParameterEncoding = JSONEncoding.default
    ) -> Call<ResponseType> {
        var request = self
        request.task = .requestCompositeParameters(
            bodyParameters: body,
            bodyEncoding: bodyEncoding,
            urlParameters: query
        )
        return request
    }
    
    // MARK: - Upload Configuration
    
    /// Configures the request to upload a file.
    ///
    /// - Parameter url: The local file URL to upload.
    /// - Returns: A new call configured for file upload.
    public func upload(file url: URL) -> Call<ResponseType> {
        var request = self
        request.task = .uploadFile(url)
        return request
    }
    
    /// Configures the request to upload multipart form data.
    ///
    /// - Parameter formData: The multipart form data to upload.
    /// - Returns: A new call configured for multipart upload.
    public func upload(multipart formData: MultipartFormData) -> Call<ResponseType> {
        var request = self
        request.task = .uploadMultipartFormData(formData)
        return request
    }
    
    /// Configures the request to upload multipart form data from body parts.
    ///
    /// - Parameter parts: The body parts to upload.
    /// - Returns: A new call configured for multipart upload.
    public func upload(multipart parts: [MultipartFormBodyPart]) -> Call<ResponseType> {
        var request = self
        request.task = .uploadMultipartFormData(MultipartFormData(parts: parts))
        return request
    }
    
    /// Configures the request to upload multipart form data with URL query parameters.
    ///
    /// - Parameters:
    ///   - formData: The multipart form data to upload.
    ///   - query: URL query parameters.
    /// - Returns: A new call configured for multipart upload with query parameters.
    public func upload(
        multipart formData: MultipartFormData,
        query: [String: Any]
    ) -> Call<ResponseType> {
        var request = self
        request.task = .uploadCompositeMultipartFormData(formData, urlParameters: query)
        return request
    }
    
    // MARK: - Download Configuration
    
    /// Configures the request to download a file.
    ///
    /// - Parameter destination: A closure that determines where to save the downloaded file.
    /// - Returns: A new call configured for file download.
    public func download(to destination: @escaping DownloadDestination) -> Call<ResponseType> {
        var request = self
        request.task = .downloadDestination(destination)
        return request
    }
    
    /// Configures the request to download a file with parameters.
    ///
    /// - Parameters:
    ///   - parameters: Request parameters.
    ///   - encoding: The parameter encoding. Default is URL encoding.
    ///   - destination: A closure that determines where to save the downloaded file.
    /// - Returns: A new call configured for file download with parameters.
    public func download(
        parameters: [String: Any],
        encoding: ParameterEncoding = URLEncoding.default,
        to destination: @escaping DownloadDestination
    ) -> Call<ResponseType> {
        var request = self
        request.task = .downloadParameters(parameters: parameters, encoding: encoding, destination: destination)
        return request
    }
    
    // MARK: - Validation Configuration
    
    /// Sets the validation type for response status codes.
    ///
    /// - Parameter type: The validation type to use.
    /// - Returns: A new call with the updated validation.
    public func validate(_ type: ValidationType) -> Call<ResponseType> {
        var request = self
        request.validationType = type
        return request
    }
    
    /// Enables validation for success status codes (2xx).
    ///
    /// - Returns: A new call that validates for 2xx status codes.
    public func validateSuccessCodes() -> Call<ResponseType> {
        validate(.successCodes)
    }
    
    /// Enables validation for success and redirect status codes (2xx, 3xx).
    ///
    /// - Returns: A new call that validates for 2xx and 3xx status codes.
    public func validateSuccessAndRedirectCodes() -> Call<ResponseType> {
        validate(.successAndRedirectCodes)
    }
    
    /// Enables validation for custom status codes.
    ///
    /// - Parameter statusCodes: The acceptable status codes.
    /// - Returns: A new call that validates for the specified status codes.
    public func validate(statusCodes: [Int]) -> Call<ResponseType> {
        validate(.customCodes(statusCodes))
    }
    
    // MARK: - Other Configuration
    
    /// Sets a custom base URL, overriding the global configuration.
    ///
    /// - Parameter url: The base URL to use.
    /// - Returns: A new call with the custom base URL.
    public func baseURL(_ url: URL?) -> Call<ResponseType> {
        var request = self
        request._baseURL = url
        return request
    }
    
    /// Sets a custom base URL from a string, overriding the global configuration.
    ///
    /// - Parameter urlString: The base URL string.
    /// - Returns: A new call with the custom base URL.
    public func baseURL(_ urlString: String) -> Call<ResponseType> {
        var request = self
        request._baseURL = URL(string: urlString)
        return request
    }
    
    /// Sets a custom JSON decoder for response parsing.
    ///
    /// - Parameter decoder: The JSON decoder to use.
    /// - Returns: A new call with the custom decoder.
    public func decoder(_ decoder: JSONDecoder) -> Call<ResponseType> {
        var request = self
        request.decoder = decoder
        return request
    }
    
    /// Sets a completion handler for processing decoded Alamofire response.
    ///
    /// Use this for generic response processing logic that applies across requests,
    /// such as storing to database, caching results, or showing error messages.
    ///
    /// This handler is called after the request completes and response is decoded,
    /// providing the typed model for direct processing.
    ///
    /// Example:
    /// ```swift
    /// Call<Meet>()
    ///     .path("/meets/\(id)")
    ///     .onComplete { resp in
    ///         switch resp.result {
    ///         case .success(let model):
    ///             AppDatabase.shared.saveMeet(model)
    ///         case .failure:
    ///             resp.errorMessage()?.showMessage()
    ///         }
    ///     }
    ///     .fetch()
    /// ```
    ///
    /// - Parameter handler: A closure called with the decoded Alamofire response.
    /// - Returns: A new call with the completion handler.
    public func onComplete(_ handler: @escaping @Sendable (AFDataResponse<ResponseType>) -> Void) -> Call<ResponseType> {
        var request = self
        request.onCompleteHandler = handler
        return request
    }
    
    // MARK: - Stub Configuration
    
    /// Sets stub data from raw Data.
    ///
    /// - Parameter data: The data to return when stubbing.
    /// - Returns: A new call with the stub data.
    public func stub(_ data: Data) -> Call<ResponseType> {
        var request = self
        request.sampleData = data
        request._sampleResponseClosure = { .networkResponse(200, data) }
        return request
    }
    
    /// Sets stub data with a custom HTTP status code.
    ///
    /// - Parameters:
    ///   - statusCode: The HTTP status code to return when stubbing.
    ///   - data: The data to return when stubbing.
    /// - Returns: A new call with the stub response.
    public func stub(statusCode: Int, data: Data) -> Call<ResponseType> {
        var request = self
        request.sampleData = data
        request._sampleResponseClosure = { .networkResponse(statusCode, data) }
        return request
    }
    
    /// Sets a fully custom HTTP response for stubbing.
    ///
    /// - Parameters:
    ///   - response: The HTTP response to return when stubbing.
    ///   - data: The data to return when stubbing.
    /// - Returns: A new call with the stub response.
    public func stub(response: HTTPURLResponse, data: Data) -> Call<ResponseType> {
        var request = self
        request.sampleData = data
        request._sampleResponseClosure = { .response(response, data) }
        return request
    }
    
    /// Sets a network error for stubbing.
    ///
    /// - Parameter error: The error to return when stubbing.
    /// - Returns: A new call with the stub error.
    public func stub(error: NSError) -> Call<ResponseType> {
        var request = self
        request._sampleResponseClosure = { .networkError(error) }
        return request
    }
    
    /// Sets stub data from an Encodable object.
    ///
    /// - Parameters:
    ///   - model: The model to encode as stub data.
    ///   - encoder: The encoder to use. Defaults to `Iris.configuration.jsonEncoder`.
    /// - Returns: A new call with the encoded stub data.
    public func stub<T: Encodable>(_ model: T, encoder: JSONEncoder = Iris.configuration.jsonEncoder) -> Call<ResponseType> {
        stub((try? encoder.encode(model)) ?? Data())
    }
    
    /// Sets stub data from a string.
    ///
    /// - Parameter string: The string to use as stub data (encoded as UTF-8).
    /// - Returns: A new call with the string stub data.
    public func stub(_ string: String) -> Call<ResponseType> {
        stub(string.data(using: .utf8) ?? Data())
    }
    
    /// Sets the stub behavior, overriding the global configuration.
    ///
    /// - Parameter behavior: The stub behavior to use.
    /// - Returns: A new call with the stub behavior.
    public func stub(behavior: StubBehavior) -> Call<ResponseType> {
        var request = self
        request.stubBehavior = behavior
        return request
    }
    
    // MARK: - Execution
    
    /// Sends the request and returns the full response.
    ///
    /// Use this when you need access to response metadata (status code, headers, etc.)
    /// in addition to the decoded model.
    ///
    /// - Returns: A `Response<ResponseType>` containing the model and metadata.
    /// - Throws: `IrisError` if the request fails.
    public func fire() async throws -> Response<ResponseType> {
        return try await Iris.send(self)
    }
    
    /// Sends the request and returns the decoded model directly.
    ///
    /// This is a convenience method for when you only need the model.
    ///
    /// - Returns: The decoded model.
    /// - Throws: `IrisError` if the request fails.
    public func fetch() async throws -> ResponseType {
        return try await Iris.fetch(self)
    }
}

// MARK: - Convenience Static Methods

public extension Call where ResponseType == Empty {
    
    /// Creates a request that doesn't expect a response model.
    ///
    /// Use this for requests where the response body is not needed
    /// or is empty (e.g., DELETE requests).
    ///
    /// - Returns: A new call with `Empty` response type.
    static func empty() -> Call<Empty> {
        Call<Empty>()
    }
}

// MARK: - Empty Response

/// A type representing an empty response.
///
/// Use `Empty` as the response type for requests that don't return a body
/// or when you don't need to parse the response.

/// A type that accepts any JSON response without parsing.
public struct Empty: Decodable {
    
    /// Creates an empty instance.
    public init() {}
    
    /// Creates an empty instance from any decoder content.
    public init(from decoder: Decoder) throws {
        // Accept any response without parsing
    }
}
