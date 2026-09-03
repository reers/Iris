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
/// Use a `Decodable` model for JSON, `Call.data()` for the raw body, or
/// `Call.empty()` when the body is unused.
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
    
    /// When `true`, a data task consumes the body as chunks instead of one buffer.
    ///
    /// File upload and file-download tasks ignore this flag. Pair with `onChunk`
    /// for incremental delivery; the concatenated body is still decoded in `finish()`.
    public var isStream: Bool = false
    
    /// Upload progress sidecar. Does not start the request; pair with `send()` / `fetch()`.
    /// Invoked on `uploadProgressQueue`.
    var uploadProgressHandler: ((Progress) -> Void)?
    
    /// Queue for `uploadProgressHandler`. Defaults to the main queue.
    var uploadProgressQueue: DispatchQueue = .main
    
    /// Download progress sidecar. Does not start the request; pair with `send()` / `fetch()`.
    /// Invoked on `downloadProgressQueue`.
    var downloadProgressHandler: ((Progress) -> Void)?
    
    /// Queue for `downloadProgressHandler`. Defaults to the main queue.
    var downloadProgressQueue: DispatchQueue = .main
    
    /// Stream chunk sidecar. Invoked on `chunkQueue` for each body fragment when `isStream` is true.
    var chunkHandler: ((Data) -> Void)?
    
    /// Queue for `chunkHandler`. Defaults to the main queue.
    var chunkQueue: DispatchQueue = .main
    
    /// Side-channel handler invoked from `finish()` after decode, before `send()` returns.
    ///
    /// Does not start the request. Use `onComplete(_:)` for cache / database / shared
    /// error UI. Call-site results belong on `send(on:completion:)` / `fetch(on:completion:)`.
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
    
    /// Observes upload progress while the request is in flight.
    ///
    /// This is a sidecar on the recipe, not an execution method. Attach it before
    /// `send()` / `fetch()` (or their completion overloads). Alamofire invokes the
    /// handler on `queue` as bytes are sent. When `Content-Length` is missing,
    /// `fractionCompleted` may stay `0`.
    ///
    /// - Parameters:
    ///   - queue: The queue for progress callbacks. Defaults to the main queue.
    ///   - handler: Called with Foundation `Progress`.
    /// - Returns: A new call with the progress handler.
    public func onUploadProgress(
        on queue: DispatchQueue = .main,
        _ handler: @escaping (Progress) -> Void
    ) -> Call<ResponseType> {
        var request = self
        request.uploadProgressHandler = handler
        request.uploadProgressQueue = queue
        return request
    }
    
    /// Observes download progress while the request is in flight.
    ///
    /// This is a sidecar on the recipe, not an execution method. Attach it before
    /// `send()` / `fetch()` (or their completion overloads). When `Content-Length`
    /// is missing, `fractionCompleted` may stay `0`.
    ///
    /// - Parameters:
    ///   - queue: The queue for progress callbacks. Defaults to the main queue.
    ///   - handler: Called with Foundation `Progress`.
    /// - Returns: A new call with the progress handler.
    public func onDownloadProgress(
        on queue: DispatchQueue = .main,
        _ handler: @escaping (Progress) -> Void
    ) -> Call<ResponseType> {
        var request = self
        request.downloadProgressHandler = handler
        request.downloadProgressQueue = queue
        return request
    }
    
    /// Receives each chunk of a streaming HTTP response body.
    ///
    /// Combine with `stream()`. This is a sidecar, not an execution method: the
    /// terminal result still arrives via `send()` / `fetch()` (or their completion
    /// overloads). Plugins and `onComplete` still run once at the end, on the
    /// concatenated body.
    ///
    /// - Parameters:
    ///   - queue: The queue for chunk callbacks. Defaults to the main queue.
    ///   - handler: Called with each `Data` fragment.
    /// - Returns: A new call with the chunk handler.
    public func onChunk(
        on queue: DispatchQueue = .main,
        _ handler: @escaping (Data) -> Void
    ) -> Call<ResponseType> {
        var request = self
        request.chunkHandler = handler
        request.chunkQueue = queue
        return request
    }
    
    /// Consumes the response body as a stream of chunks instead of one buffer.
    ///
    /// Has no effect on file upload or file-download tasks. Chunks are delivered
    /// to `onChunk`. After the stream ends, `Empty` discards the concatenated body,
    /// `Data` / `String` keep it as the raw model, and other `Decodable` types
    /// JSON-decode the concatenation.
    ///
    /// - Returns: A new call marked for streaming.
    public func stream() -> Call<ResponseType> {
        var request = self
        request.isStream = true
        return request
    }
    
    /// Side-channel hook invoked from `finish()` after decode, before `send()` returns.
    ///
    /// Use this for generic processing that applies across requests (cache, database,
    /// shared error UI). It does **not** start the request and is not a substitute
    /// for `send(on:completion:)`.
    ///
    /// If both are chained, both fire: `onComplete` first on the current thread with
    /// `AFDataResponse`, then the completion wrapper on its queue with
    /// `Result<Response, IrisError>`.
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
    public func send() async throws -> Response<ResponseType> {
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
    
    /// Sends the request and delivers the result to a completion handler.
    ///
    /// Thin wrapper over `send()`. Use this to migrate callback-style call sites
    /// without wrapping each one in `Task { try await }`. Cancel the returned
    /// `Task` to cancel the underlying request.
    ///
    /// Distinct from `onComplete`, which is a sidecar on the recipe and never
    /// starts work. This method is the execution entry; `onComplete` still runs
    /// inside `finish()` if both are set.
    ///
    /// - Parameters:
    ///   - queue: The queue for `completion`. Defaults to the main queue.
    ///   - completion: Called once with success or `IrisError`.
    /// - Returns: The unstructured task running the request.
    @discardableResult
    public func send(
        on queue: DispatchQueue = .main,
        completion: @escaping @Sendable (Result<Response<ResponseType>, IrisError>) -> Void
    ) -> Task<Void, Never> {
        Task {
            let result: Result<Response<ResponseType>, IrisError>
            do {
                result = .success(try await send())
            } catch let error as IrisError {
                result = .failure(error)
            } catch {
                result = .failure(.underlying(error, nil))
            }
            queue.async { completion(result) }
        }
    }
    
    /// Sends the request and delivers the decoded model to a completion handler.
    ///
    /// Thin wrapper over `fetch()`. Same execution model as `send(on:completion:)`;
    /// the success value is `response.model` instead of the full `Response`.
    ///
    /// - Parameters:
    ///   - queue: The queue for `completion`. Defaults to the main queue.
    ///   - completion: Called once with the model or `IrisError`.
    /// - Returns: The unstructured task running the request.
    @discardableResult
    public func fetch(
        on queue: DispatchQueue = .main,
        completion: @escaping @Sendable (Result<ResponseType, IrisError>) -> Void
    ) -> Task<Void, Never> {
        send(on: queue) { result in
            completion(result.map(\.model))
        }
    }
}

// MARK: - Convenience Static Methods

public extension Call where ResponseType == Empty {
    
    /// Creates a request that doesn't expect a response model.
    ///
    /// Use this for requests where the response body is not needed
    /// or is empty (e.g., DELETE requests). The body is discarded.
    /// For the raw bytes, use `Call.data()` instead.
    ///
    /// - Returns: A new call with `Empty` response type.
    static func empty() -> Call<Empty> {
        Call<Empty>()
    }
}

public extension Call where ResponseType == Data {
    
    /// Creates a request that returns the raw response body.
    ///
    /// The body is not JSON-decoded. Use this for binary payloads, opaque
    /// JSON you will parse yourself, or APIs that only need a success body.
    ///
    /// - Returns: A new call whose model is the raw `Data`.
    static func data() -> Call<Data> {
        Call<Data>()
    }
}

public extension Call where ResponseType == String {
    
    /// Creates a request that returns the response body as UTF-8 text.
    ///
    /// The body is not JSON-decoded. A JSON string value keeps its quotes;
    /// use a `Decodable` model if you need JSON string decoding.
    ///
    /// - Returns: A new call whose model is the UTF-8 `String`.
    static func string() -> Call<String> {
        Call<String>()
    }
}

// MARK: - Empty Response

/// A type representing an empty response.
///
/// Use `Empty` as the response type for requests that don't return a body
/// or when you don't need to parse the response. The body is ignored.
/// Use `Call<Data>` when you need the raw bytes.

/// A type that accepts any JSON response without parsing.
public struct Empty: Decodable {
    
    /// Creates an empty instance.
    public init() {}
    
    /// Creates an empty instance from any decoder content.
    public init(from decoder: Decoder) throws {
        // Accept any response without parsing
    }
}
