//
//  Iris.swift
//  Iris
//
//  The core networking engine for Iris, featuring async/await based request execution.
//

import Foundation
import Alamofire
import os.lock

private final class AlamofireRequestCancellationToken {
    private let lock: os_unfair_lock_t
    private var request: Request?
    private var isCancelled = false
    
    init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock_s())
    }
    
    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }
    
    func setRequest(_ request: Request) {
        os_unfair_lock_lock(lock)
        if isCancelled {
            os_unfair_lock_unlock(lock)
            request.cancel()
            return
        }
        
        self.request = request
        os_unfair_lock_unlock(lock)
    }
    
    func cancel() {
        os_unfair_lock_lock(lock)
        isCancelled = true
        let request = request
        os_unfair_lock_unlock(lock)
        
        request?.cancel()
    }
}

/// Accumulates streamed body fragments and resumes the request continuation once.
///
/// Alamofire may deliver `stream` and `complete` events on a concurrent queue, so
/// `chunks` and `didFinish` are guarded by `os_unfair_lock`. `@unchecked Sendable`
/// is valid because every mutable field is accessed only while that lock is held,
/// and `complete` resumes the continuation outside the lock.
private final class StreamAccumulation: @unchecked Sendable {
    private let lock: os_unfair_lock_t
    private var chunks = Data()
    private var didFinish = false
    
    init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock_s())
    }
    
    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }
    
    func append(_ data: Data) {
        os_unfair_lock_lock(lock)
        chunks.append(data)
        os_unfair_lock_unlock(lock)
    }
    
    func snapshot() -> Data {
        os_unfair_lock_lock(lock)
        let data = chunks
        os_unfair_lock_unlock(lock)
        return data
    }
    
    func complete(
        _ result: Result<HTTPResponse, IrisError>,
        continuation: CheckedContinuation<Result<HTTPResponse, IrisError>, Never>
    ) {
        os_unfair_lock_lock(lock)
        let alreadyFinished = didFinish
        didFinish = true
        os_unfair_lock_unlock(lock)
        guard !alreadyFinished else { return }
        continuation.resume(returning: result)
    }
}

/// The core networking struct of Iris.
///
/// Iris provides a modern, type-safe networking layer built on top of Alamofire,
/// featuring async/await support and a chainable API for building requests.
public struct Iris {
    
    // MARK: - Public Methods
    
    /// Sends a request and returns a `Response<Model>`.
    ///
    /// This is the primary method for executing network requests. It handles both
    /// real network requests and stub responses for testing purposes.
    ///
    /// - Parameter request: The `Call` object containing all configuration for the network call.
    /// - Returns: A `Response<Model>` containing the decoded model and raw response data.
    /// - Throws: `IrisError` if the request fails or response cannot be decoded.
    public static func send<Model: Decodable>(_ request: Call<Model>) async throws -> Response<Model> {
        let broadcaster = EventBroadcaster(from: request)
        let cancellationToken = AlamofireRequestCancellationToken()
        return try await withTaskCancellationHandler {
            defer { broadcaster.finish() }
            return try await execute(request, broadcaster: broadcaster, cancellationToken: cancellationToken)
        } onCancel: {
            cancellationToken.cancel()
            broadcaster.finish()
        }
    }
    
    /// Starts the request, then runs `body` with a live `CallSession`.
    ///
    /// Progress and chunk probes are attached before `body` runs, but sidecar
    /// streams are live-only: values emitted before a stream is created are not
    /// replayed. Recipe sidecars (`onUploadProgress`, `onChunk`, `onComplete`)
    /// still fire on the same probe. After `body` returns, this awaits the
    /// network task and always returns `Response<Model>` — `body` only consumes
    /// sidecars.
    static func send<Model: Decodable>(
        _ request: Call<Model>,
        _ body: (CallSession<Model>) async throws -> Void
    ) async throws -> Response<Model> {
        let broadcaster = EventBroadcaster(from: request)
        let cancellationToken = AlamofireRequestCancellationToken()
        
        let valueTask = Task<Response<Model>, Error> {
            defer { broadcaster.finish() }
            return try await execute(request, broadcaster: broadcaster, cancellationToken: cancellationToken)
        }
        
        let session = CallSession(valueTask: valueTask, broadcaster: broadcaster)
        
        return try await withTaskCancellationHandler {
            do {
                try await body(session)
                return try await valueTask.value
            } catch {
                _ = await valueTask.result
                throw error
            }
        } onCancel: {
            valueTask.cancel()
            cancellationToken.cancel()
            broadcaster.finish()
        }
    }
    
    /// Sends a request and returns the decoded model directly.
    ///
    /// This is a convenience method that returns the decoded model from the response.
    /// Use this when you only need the decoded model and don't need access to
    /// response metadata like status codes or headers.
    ///
    /// - Parameter request: The `Call` object containing all configuration for the network call.
    /// - Returns: The decoded model of type `Model`.
    /// - Throws: `IrisError` if the request fails or response cannot be decoded.
    public static func fetch<Model: Decodable>(_ request: Call<Model>) async throws -> Model {
        let response = try await send(request)
        return response.model
    }
    
    // MARK: - Private Methods
    
    /// Stub or live request. Shared by `send()` and `send { session in }` so the
    /// session path can start this work in a sibling task without changing
    /// plugin / sidecar / decode order.
    private static func execute<Model: Decodable>(
        _ request: Call<Model>,
        broadcaster: EventBroadcaster,
        cancellationToken: AlamofireRequestCancellationToken
    ) async throws -> Response<Model> {
        // Snapshot the global configuration once so a concurrent
        // `Iris.configure(...)` cannot hand this request a mix of old and
        // new values mid-flight.
        let configuration = Iris.configuration
        let stubBehavior = request.stubBehavior ?? configuration.stubBehavior
        if let stubBehavior {
            return try await performStub(request, behavior: stubBehavior, broadcaster: broadcaster, configuration: configuration)
        }
        return try await performRequest(request, broadcaster: broadcaster, cancellationToken: cancellationToken, configuration: configuration)
    }
    
    /// Performs the actual network request using Alamofire.
    ///
    /// This method handles the complete request lifecycle:
    /// 1. Creates an `Endpoint` from the request
    /// 2. Converts the endpoint to a `URLRequest`
    /// 3. Applies plugins for request preparation
    /// 4. Executes the appropriate request type (data, upload, download)
    /// 5. Notifies plugins of response
    /// 6. Decodes the response into the expected model type
    ///
    /// - Parameter request: The `Call` object to execute.
    /// - Returns: A `Response<Model>` containing the decoded model.
    /// - Throws: `IrisError` if any step in the request lifecycle fails.
    private static func performRequest<Model: Decodable>(
        _ request: Call<Model>,
        broadcaster: EventBroadcaster,
        cancellationToken: AlamofireRequestCancellationToken,
        configuration: IrisConfiguration
    ) async throws -> Response<Model> {
        let urlRequest = try makeURLRequest(from: request, configuration: configuration)
        
        // 4. Create interceptor (bridges Plugin system to Alamofire)
        // Capture plugins array to satisfy Sendable requirement
        let plugins = configuration.plugins
        let interceptor = IrisCallInterceptor(
            prepare: { @Sendable urlRequest in
                plugins.reduce(urlRequest) { $1.prepare($0, target: request) }
            }
        )
        
        // 5. Execute request based on task type. Network methods return Result
        // so failures still flow through plugin didReceive/process.
        let session = configuration.session
        let networkResult: Result<HTTPResponse, IrisError>
        
        switch request.task {
        case .uploadFile(let fileURL):
            networkResult = await performUploadFile(urlRequest, fileURL: fileURL, interceptor: interceptor, session: session, request: request, plugins: plugins, broadcaster: broadcaster, cancellationToken: cancellationToken)
            
        case .uploadMultipartFormData(let formData):
            networkResult = await performUploadMultipart(urlRequest, formData: formData, interceptor: interceptor, session: session, request: request, plugins: plugins, broadcaster: broadcaster, cancellationToken: cancellationToken)
            
        case .uploadCompositeMultipartFormData(let formData, _):
            networkResult = await performUploadMultipart(urlRequest, formData: formData, interceptor: interceptor, session: session, request: request, plugins: plugins, broadcaster: broadcaster, cancellationToken: cancellationToken)
            
        case .downloadDestination(let destination):
            networkResult = await performDownload(urlRequest, destination: destination, interceptor: interceptor, session: session, request: request, plugins: plugins, broadcaster: broadcaster, cancellationToken: cancellationToken)
            
        case .downloadParameters(_, _, let destination):
            networkResult = await performDownload(urlRequest, destination: destination, interceptor: interceptor, session: session, request: request, plugins: plugins, broadcaster: broadcaster, cancellationToken: cancellationToken)
            
        default:
            // Data tasks only. File upload/download ignore `stream()`.
            if request.isStream {
                networkResult = await performStream(urlRequest, interceptor: interceptor, session: session, request: request, plugins: plugins, broadcaster: broadcaster, cancellationToken: cancellationToken)
            } else {
                networkResult = await performDataRequest(urlRequest, interceptor: interceptor, session: session, request: request, plugins: plugins, broadcaster: broadcaster, cancellationToken: cancellationToken)
            }
        }
        
        // 6-8. Notify plugins, process, then decode or throw
        return try finish(networkResult, request: request, configuration: configuration)
    }
    
    /// Decodes the response data into the specified model type.
    ///
    /// `Empty` skips decoding. `Data` and `String` use the raw HTTP body
    /// rather than JSON (`HTTPResponse.map`).
    ///
    /// - Parameters:
    ///   - type: The type to decode the response into.
    ///   - rawResponse: The HTTP response containing the data to decode.
    ///   - customDecoder: An optional custom JSON decoder. If nil, uses the global configuration decoder.
    /// - Returns: The decoded model.
    /// - Throws: `IrisError.objectMapping` if decoding fails.
    private static func decodeModel<Model: Decodable>(
        _ type: Model.Type,
        from rawResponse: HTTPResponse,
        using customDecoder: JSONDecoder?,
        configuration: IrisConfiguration
    ) throws -> Model {
        let decoder = customDecoder ?? configuration.jsonDecoder
        
        if Model.self == Empty.self {
            return Empty() as! Model
        }
        
        return try rawResponse.map(Model.self, using: decoder)
    }
    
    /// Notifies plugins, applies `process`, then decodes or throws.
    ///
    /// Both success and failure results pass through `didReceive` and `process`
    /// so plugins can log errors, hide activity indicators, or recover failures.
    private static func finish<Model: Decodable>(
        _ result: Result<HTTPResponse, IrisError>,
        request: Call<Model>,
        configuration: IrisConfiguration
    ) throws -> Response<Model> {
        configuration.plugins.forEach { $0.didReceive(result, target: request) }
        
        var processedResult = result
        for plugin in configuration.plugins {
            processedResult = plugin.process(processedResult, target: request)
        }
        
        switch processedResult {
        case .success(let rawResponse):
            do {
                let model = try decodeModel(Model.self, from: rawResponse, using: request.decoder, configuration: configuration)
                
                if let onCompleteHandler = request.onCompleteHandler {
                    let afResponse = DataResponse<Model, AFError>(
                        request: rawResponse.request,
                        response: rawResponse.response,
                        data: rawResponse.data,
                        metrics: nil,
                        serializationDuration: 0,
                        result: .success(model)
                    )
                    onCompleteHandler(afResponse)
                }
                
                return Response(model: model, httpResponse: rawResponse)
            } catch {
                if let onCompleteHandler = request.onCompleteHandler {
                    let afError = AFError.responseSerializationFailed(reason: .decodingFailed(error: error))
                    let afResponse = DataResponse<Model, AFError>(
                        request: rawResponse.request,
                        response: rawResponse.response,
                        data: rawResponse.data,
                        metrics: nil,
                        serializationDuration: 0,
                        result: .failure(afError)
                    )
                    onCompleteHandler(afResponse)
                }
                throw error
            }
        case .failure(let error):
            if let onCompleteHandler = request.onCompleteHandler {
                let afError: AFError
                switch error {
                case .underlying(let underlying, _):
                    afError = underlying as? AFError ?? AFError.sessionTaskFailed(error: underlying)
                case .statusCode(let response):
                    afError = AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: response.statusCode))
                default:
                    afError = AFError.sessionTaskFailed(error: error)
                }
                let raw = error.response
                let afResponse = DataResponse<Model, AFError>(
                    request: raw?.request,
                    response: raw?.response,
                    data: raw?.data,
                    metrics: nil,
                    serializationDuration: 0,
                    result: .failure(afError)
                )
                onCompleteHandler(afResponse)
            }
            throw error
        }
    }
    
    /// Maps an Alamofire callback into a plugin-facing result.
    ///
    /// An HTTP response with a transport/validation error becomes `.statusCode`.
    /// A failure with no HTTP response (timeout, DNS, connectivity) becomes `.underlying`.
    static func mapNetworkResult(
        data: Data,
        request: URLRequest?,
        response: HTTPURLResponse?,
        error: Error?
    ) -> Result<HTTPResponse, IrisError> {
        let rawResponse = HTTPResponse(
            statusCode: response?.statusCode ?? 0,
            data: data,
            request: request,
            response: response
        )
        
        guard let error else {
            return .success(rawResponse)
        }
        
        if response != nil {
            return .failure(.statusCode(rawResponse))
        }
        return .failure(.underlying(error, rawResponse))
    }
    
    /// Attaches Alamofire progress closures as siblings of the response handler.
    ///
    /// The closures feed `EventBroadcaster`, which multicasts to recipe handlers and
    /// `CallSession` streams. Always attached so `send { session in }` can observe
    /// progress even when the recipe has no `onUploadProgress` / `onDownloadProgress`.
    private static func attachSidecars<Model: Decodable>(
        _ afRequest: AFRequest,
        from request: Call<Model>,
        broadcaster: EventBroadcaster
    ) {
        afRequest.uploadProgress(queue: request.uploadProgressQueue) { progress in
            broadcaster.yieldUpload(progress, handlerOnQueue: true)
        }
        afRequest.downloadProgress(queue: request.downloadProgressQueue) { progress in
            broadcaster.yieldDownload(progress, handlerOnQueue: true)
        }
    }
    
    private static func mapDataResponse(_ afResponse: AFDataResponse<Data>) -> Result<HTTPResponse, IrisError> {
        switch afResponse.result {
        case .success(let data):
            return mapNetworkResult(
                data: data,
                request: afResponse.request,
                response: afResponse.response,
                error: nil
            )
        case .failure(let error):
            return mapNetworkResult(
                data: afResponse.data ?? Data(),
                request: afResponse.request,
                response: afResponse.response,
                error: error
            )
        }
    }
    
    private static func mapDownloadResponse(_ afResponse: DownloadResponse<Data, AFError>) -> Result<HTTPResponse, IrisError> {
        switch afResponse.result {
        case .success(let data):
            return mapNetworkResult(
                data: data,
                request: afResponse.request,
                response: afResponse.response,
                error: nil
            )
        case .failure(let error):
            return mapNetworkResult(
                data: afResponse.resumeData ?? Data(),
                request: afResponse.request,
                response: afResponse.response,
                error: error
            )
        }
    }
    
    private static func performDataResponseRequest<Model: Decodable>(
        request: Call<Model>,
        broadcaster: EventBroadcaster,
        cancellationToken: AlamofireRequestCancellationToken,
        buildRequest: () -> AFDataRequest
    ) async -> Result<HTTPResponse, IrisError> {
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let validationCodes = request.validationType.statusCodes
                var afRequest = buildRequest()
                
                if !validationCodes.isEmpty {
                    afRequest = afRequest.validate(statusCode: validationCodes)
                }
                
                cancellationToken.setRequest(afRequest)
                attachSidecars(afRequest, from: request, broadcaster: broadcaster)
                
                afRequest.responseData { afResponse in
                    continuation.resume(returning: mapDataResponse(afResponse))
                }
            }
        } onCancel: {
            cancellationToken.cancel()
        }
    }
    
    private static func performDownloadResponseRequest<Model: Decodable>(
        request: Call<Model>,
        broadcaster: EventBroadcaster,
        cancellationToken: AlamofireRequestCancellationToken,
        buildRequest: () -> AFDownloadRequest
    ) async -> Result<HTTPResponse, IrisError> {
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let validationCodes = request.validationType.statusCodes
                var afRequest = buildRequest()
                
                if !validationCodes.isEmpty {
                    afRequest = afRequest.validate(statusCode: validationCodes)
                }
                
                cancellationToken.setRequest(afRequest)
                attachSidecars(afRequest, from: request, broadcaster: broadcaster)
                
                afRequest.responseData { afResponse in
                    continuation.resume(returning: mapDownloadResponse(afResponse))
                }
            }
        } onCancel: {
            cancellationToken.cancel()
        }
    }
    
    private static func configureWillSend<Model: Decodable>(
        _ afRequest: AFRequest,
        interceptor: IrisCallInterceptor,
        request: Call<Model>,
        plugins: [PluginType]
    ) {
        interceptor.willSend = { @Sendable [weak afRequest] urlRequest in
            guard let afRequest else {
                let callType = CallTypeWrapper(alamofireRequest: nil, urlRequest: urlRequest)
                plugins.forEach { $0.willSend(callType, target: request) }
                return
            }

            let callType = CallTypeWrapper(alamofireRequest: afRequest, urlRequest: urlRequest)
            plugins.forEach { $0.willSend(callType, target: request) }
        }
    }

    /// Streams the HTTP response body as chunks, then finishes with the concatenated data.
    ///
    /// Each fragment is forwarded to `onChunk` on `chunkQueue`. The concatenated body
    /// becomes the terminal `HTTPResponse` so plugins `didReceive` / `process` and
    /// `onComplete` still run once in `finish()`, same as a buffered data request.
    /// `automaticallyCancelOnStreamError` is false so transport errors still map through
    /// `mapNetworkResult` instead of cancelling the Alamofire request first.
    private static func performStream<Model: Decodable>(
        _ urlRequest: URLRequest,
        interceptor: IrisCallInterceptor,
        session: Session,
        request: Call<Model>,
        plugins: [PluginType],
        broadcaster: EventBroadcaster,
        cancellationToken: AlamofireRequestCancellationToken
    ) async -> Result<HTTPResponse, IrisError> {
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let accumulation = StreamAccumulation()
                let streamRequest = session.requestQueue.sync {
                    let streamRequest = session.streamRequest(
                        urlRequest,
                        automaticallyCancelOnStreamError: false,
                        interceptor: interceptor
                    )
                    configureWillSend(streamRequest, interceptor: interceptor, request: request, plugins: plugins)
                    return streamRequest
                }
                attachSidecars(streamRequest, from: request, broadcaster: broadcaster)
                cancellationToken.setRequest(streamRequest)
                
                let validationCodes = request.validationType.statusCodes
                
                streamRequest.responseStream(on: request.chunkQueue) { stream in
                    switch stream.event {
                    case .stream(.success(let data)):
                        accumulation.append(data)
                        broadcaster.yieldChunk(data, handlerOnQueue: true)
                    case .complete(let completion):
                        let data = accumulation.snapshot()
                        if let error = completion.error {
                            accumulation.complete(
                                mapNetworkResult(
                                    data: data,
                                    request: completion.request,
                                    response: completion.response,
                                    error: error
                                ),
                                continuation: continuation
                            )
                        } else {
                            let httpResponse = HTTPResponse(
                                statusCode: completion.response?.statusCode ?? 0,
                                data: data,
                                request: completion.request,
                                response: completion.response
                            )
                            if !validationCodes.isEmpty && !validationCodes.contains(httpResponse.statusCode) {
                                accumulation.complete(.failure(.statusCode(httpResponse)), continuation: continuation)
                            } else {
                                accumulation.complete(.success(httpResponse), continuation: continuation)
                            }
                        }
                    }
                }
            }
        } onCancel: {
            cancellationToken.cancel()
        }
    }
    
    /// Resolves the final URL for a request path.
    ///
    /// Absolute paths are used directly. Relative paths are resolved against
    /// the request's configured base URL.
    static func resolveURL(baseURL: URL?, path: String) throws -> URL {
        if let url = URL(string: path), url.scheme != nil, url.host != nil {
            return url
        }
        
        guard let baseURL,
              let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              url.scheme != nil,
              url.host != nil else {
            throw IrisError.requestMapping(path)
        }
        
        return url
    }
    
    /// Creates an `Endpoint` from the given request.
    ///
    /// - Parameter request: The request to convert.
    /// - Returns: An `Endpoint` representing the request.
    private static func createEndpoint<Model: Decodable>(from request: Call<Model>, configuration: IrisConfiguration) throws -> Endpoint {
        let url = try resolveURL(baseURL: request.configuredBaseURL(over: configuration), path: request.path).absoluteString
        
        return Endpoint(
            url: url,
            sampleResponseClosure: request.sampleResponseClosure,
            method: request.method,
            task: request.task,
            httpHeaderFields: request.headers
        )
    }
    
    private static func makeURLRequest<Model: Decodable>(
        from request: Call<Model>,
        configuration: IrisConfiguration
    ) throws -> URLRequest {
        let endpoint = try createEndpoint(from: request, configuration: configuration)
        var urlRequest = try endpoint.urlRequest()
        urlRequest.timeoutInterval = request.timeout(over: configuration)

        var headers = configuration.defaultHeaders
        if let serviceHeaders = request.service?.headers {
            headers.mergeHTTPHeaderFields(serviceHeaders)
        }
        if let requestHeaders = request.headers {
            headers.mergeHTTPHeaderFields(requestHeaders)
        }
        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        return urlRequest
    }

    /// Performs a standard data request using Alamofire.
    ///
    /// - Parameters:
    ///   - urlRequest: The URL request to execute.
    ///   - interceptor: The request interceptor for plugin integration.
    ///   - request: The original request for validation configuration.
    /// - Returns: A result containing the response data or an `IrisError`.
    private static func performDataRequest<Model: Decodable>(
        _ urlRequest: URLRequest,
        interceptor: IrisCallInterceptor,
        session: Session,
        request: Call<Model>,
        plugins: [PluginType],
        broadcaster: EventBroadcaster,
        cancellationToken: AlamofireRequestCancellationToken
    ) async -> Result<HTTPResponse, IrisError> {
        await performDataResponseRequest(request: request, broadcaster: broadcaster, cancellationToken: cancellationToken) {
            session.requestQueue.sync {
                let afRequest = session.request(urlRequest, interceptor: interceptor)
                configureWillSend(afRequest, interceptor: interceptor, request: request, plugins: plugins)
                return afRequest
            }
        }
    }
    
    /// Performs a file upload request.
    ///
    /// - Parameters:
    ///   - urlRequest: The URL request to execute.
    ///   - fileURL: The local file URL to upload.
    ///   - interceptor: The request interceptor for plugin integration.
    ///   - request: The original request for validation configuration.
    /// - Returns: A result containing the response data or an `IrisError`.
    private static func performUploadFile<Model: Decodable>(
        _ urlRequest: URLRequest,
        fileURL: URL,
        interceptor: IrisCallInterceptor,
        session: Session,
        request: Call<Model>,
        plugins: [PluginType],
        broadcaster: EventBroadcaster,
        cancellationToken: AlamofireRequestCancellationToken
    ) async -> Result<HTTPResponse, IrisError> {
        await performDataResponseRequest(request: request, broadcaster: broadcaster, cancellationToken: cancellationToken) {
            session.requestQueue.sync {
                let afRequest = session.upload(fileURL, with: urlRequest, interceptor: interceptor)
                configureWillSend(afRequest, interceptor: interceptor, request: request, plugins: plugins)
                return afRequest
            }
        }
    }
    
    /// Performs a multipart form data upload request.
    ///
    /// - Parameters:
    ///   - urlRequest: The URL request to execute.
    ///   - formData: The multipart form data to upload.
    ///   - interceptor: The request interceptor for plugin integration.
    ///   - request: The original request for validation configuration.
    /// - Returns: A result containing the response data or an `IrisError`.
    private static func performUploadMultipart<Model: Decodable>(
        _ urlRequest: URLRequest,
        formData: MultipartFormData,
        interceptor: IrisCallInterceptor,
        session: Session,
        request: Call<Model>,
        plugins: [PluginType],
        broadcaster: EventBroadcaster,
        cancellationToken: AlamofireRequestCancellationToken
    ) async -> Result<HTTPResponse, IrisError> {
        await performDataResponseRequest(request: request, broadcaster: broadcaster, cancellationToken: cancellationToken) {
            session.requestQueue.sync {
                let afFormData = RequestMultipartFormData(fileManager: formData.fileManager, boundary: formData.boundary)
                afFormData.applyMoyaMultipartFormData(formData)
                let afRequest = session.upload(multipartFormData: afFormData, with: urlRequest, interceptor: interceptor)
                configureWillSend(afRequest, interceptor: interceptor, request: request, plugins: plugins)
                return afRequest
            }
        }
    }
    
    /// Performs a file download request.
    ///
    /// - Parameters:
    ///   - urlRequest: The URL request to execute.
    ///   - destination: The closure determining where to save the downloaded file.
    ///   - interceptor: The request interceptor for plugin integration.
    ///   - request: The original request for validation configuration.
    /// - Returns: A result containing the response data or an `IrisError`.
    private static func performDownload<Model: Decodable>(
        _ urlRequest: URLRequest,
        destination: @escaping DownloadDestination,
        interceptor: IrisCallInterceptor,
        session: Session,
        request: Call<Model>,
        plugins: [PluginType],
        broadcaster: EventBroadcaster,
        cancellationToken: AlamofireRequestCancellationToken
    ) async -> Result<HTTPResponse, IrisError> {
        await performDownloadResponseRequest(request: request, broadcaster: broadcaster, cancellationToken: cancellationToken) {
            session.requestQueue.sync {
                let afRequest = session.download(urlRequest, interceptor: interceptor, to: destination)
                configureWillSend(afRequest, interceptor: interceptor, request: request, plugins: plugins)
                return afRequest
            }
        }
    }
    
    /// Performs a stub request for testing purposes.
    ///
    /// This method simulates a network request by returning the sample data
    /// configured on the request. It respects the stub behavior configuration
    /// to optionally add a delay before returning.
    ///
    /// - Parameters:
    ///   - request: The request containing the sample data.
    ///   - behavior: The stub behavior determining timing of the response.
    /// - Returns: A `Response<Model>` containing the decoded stub data.
    /// - Throws: `IrisError` if decoding the stub data fails.
    private static func performStub<Model: Decodable>(
        _ request: Call<Model>,
        behavior: StubBehavior,
        broadcaster: EventBroadcaster,
        configuration: IrisConfiguration
    ) async throws -> Response<Model> {
        // Calculate delay
        let delay: TimeInterval
        switch behavior {
        case .immediate:
            delay = 0
        case .delayed(let interval):
            delay = interval
        }
        
        // Apply delay
        if delay > 0 {
            try await _Concurrency.Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        let stubRequest = try? makeURLRequest(from: request, configuration: configuration)
        let callType = CallTypeWrapper(alamofireRequest: nil, urlRequest: stubRequest)
        configuration.plugins.forEach { $0.willSend(callType, target: request) }
        
        let result: Result<HTTPResponse, IrisError>
        let stubData: Data
        switch request.sampleResponseClosure() {
        case .networkResponse(let statusCode, let data):
            stubData = data
            let rawResponse = HTTPResponse(statusCode: statusCode, data: data)
            if request.validationType.statusCodes.isEmpty || request.validationType.statusCodes.contains(statusCode) {
                result = .success(rawResponse)
            } else {
                result = .failure(.statusCode(rawResponse))
            }
            
        case .response(let response, let data):
            stubData = data
            let rawResponse = HTTPResponse(
                statusCode: response.statusCode,
                data: data,
                request: nil,
                response: response
            )
            if request.validationType.statusCodes.isEmpty || request.validationType.statusCodes.contains(response.statusCode) {
                result = .success(rawResponse)
            } else {
                result = .failure(.statusCode(rawResponse))
            }
            
        case .networkError(let error):
            stubData = Data()
            result = .failure(.underlying(error, nil))
        }
        
        broadcaster.deliverStub(data: stubData)
        return try finish(result, request: request, configuration: configuration)
    }
}

// MARK: - CallTypeWrapper

/// A simple wrapper conforming to `CallType` for plugin integration.
///
/// This wrapper is used internally to provide request information to plugins
/// during the request lifecycle.
private struct CallTypeWrapper: CallType {

    /// The underlying Alamofire request when this is a live network call.
    let alamofireRequest: AFRequest?

    /// The prepared URL request seen by the plugin.
    let urlRequest: URLRequest?

    /// The underlying URL request.
    var request: URLRequest? {
        urlRequest ?? alamofireRequest?.request
    }

    /// Additional headers from the session configuration.
    var sessionHeaders: [String: String] {
        alamofireRequest?.sessionHeaders ?? [:]
    }

    /// Authenticates the request with username and password.
    func authenticate(username: String, password: String, persistence: URLCredential.Persistence) -> Self {
        alamofireRequest?.authenticate(username: username, password: password, persistence: persistence)
        return self
    }
    
    /// Authenticates the request with a credential.
    func authenticate(with credential: URLCredential) -> Self {
        alamofireRequest?.authenticate(with: credential)
        return self
    }
    
    /// Returns a cURL representation of the request.
    func cURLDescription(calling handler: @escaping @Sendable (String) -> Void) -> Self {
        if let alamofireRequest {
            _ = alamofireRequest.cURLDescription(calling: handler)
        } else {
            handler(urlRequest?.irisCURLDescription() ?? "")
        }
        return self
    }
}
