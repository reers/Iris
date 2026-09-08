//
//  Iris.swift
//  Iris
//
//  The core networking engine for Iris, featuring async/await based request execution.
//

import Foundation
import Alamofire
import os.lock

/// `@unchecked Sendable` is valid because `request` and `isCancelled` are
/// only accessed while `lock` is held.
private final class AlamofireRequestCancellationToken: @unchecked Sendable {
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
        _ delivery: NetworkDelivery,
        continuation: CheckedContinuation<NetworkDelivery, Never>
    ) {
        os_unfair_lock_lock(lock)
        let alreadyFinished = didFinish
        didFinish = true
        os_unfair_lock_unlock(lock)
        guard !alreadyFinished else { return }
        continuation.resume(returning: delivery)
    }
}

/// Resumes a terminal stream continuation once.
private final class TerminalStreamCompletion: @unchecked Sendable {
    private let lock: os_unfair_lock_t
    private var didFinish = false
    private var didYieldChunk = false

    init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock_s())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    func finish(_ continuation: CheckedContinuation<Void, any Error>, throwing error: (any Error)? = nil) {
        os_unfair_lock_lock(lock)
        let alreadyFinished = didFinish
        didFinish = true
        os_unfair_lock_unlock(lock)
        guard !alreadyFinished else { return }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    var hasYieldedChunks: Bool {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return didYieldChunk
    }

    func markYieldedChunk() {
        os_unfair_lock_lock(lock)
        didYieldChunk = true
        os_unfair_lock_unlock(lock)
    }
}

private struct TerminalStreamBufferOverflow: Error {}

/// Lazily starts a terminal stream on first iteration and bridges callback chunks
/// into an `AsyncThrowingStream(unfolding:)` sequence.
private final class TerminalStreamEmitter<Element: Sendable>: @unchecked Sendable {
    private static var maximumBufferedBytes: Int { 16 * 1024 * 1024 }

    private let lock: os_unfair_lock_t
    private let cost: @Sendable (Element) -> Int
    private var buffered: [Element] = []
    private var bufferedBytes = 0
    private var waiter: CheckedContinuation<Element?, any Error>?
    private var didStart = false
    private var didFinish = false
    private var terminalError: (any Error)?
    private var onStart: (@Sendable () -> Void)?
    private var onCancel: (@Sendable () -> Void)?

    init(cost: @escaping @Sendable (Element) -> Int) {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock_s())
        self.cost = cost
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    func setStart(_ onStart: @escaping @Sendable () -> Void) {
        os_unfair_lock_lock(lock)
        self.onStart = onStart
        os_unfair_lock_unlock(lock)
    }

    func setCancel(_ onCancel: @escaping @Sendable () -> Void) {
        os_unfair_lock_lock(lock)
        if didFinish {
            os_unfair_lock_unlock(lock)
            onCancel()
            return
        }
        self.onCancel = onCancel
        os_unfair_lock_unlock(lock)
    }

    var shouldStartRequest: Bool {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return !didFinish
    }

    func next() async throws -> Element? {
        let cancellation = CancellationHandler(emitter: self)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let start = prepareNext(continuation)
                start?()
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func yield(_ value: Element) {
        os_unfair_lock_lock(lock)
        guard !didFinish else {
            os_unfair_lock_unlock(lock)
            return
        }
        if let waiter {
            self.waiter = nil
            os_unfair_lock_unlock(lock)
            waiter.resume(returning: value)
        } else {
            let valueCost = cost(value)
            if bufferedBytes + valueCost > Self.maximumBufferedBytes {
                didFinish = true
                terminalError = TerminalStreamBufferOverflow()
                let onCancel = self.onCancel
                self.onStart = nil
                self.onCancel = nil
                os_unfair_lock_unlock(lock)
                onCancel?()
                return
            }
            buffered.append(value)
            bufferedBytes += valueCost
            os_unfair_lock_unlock(lock)
        }
    }

    func finish(throwing error: (any Error)? = nil) {
        os_unfair_lock_lock(lock)
        guard !didFinish else {
            os_unfair_lock_unlock(lock)
            return
        }
        didFinish = true
        terminalError = error
        let waiter = self.waiter
        self.waiter = nil
        onStart = nil
        onCancel = nil
        os_unfair_lock_unlock(lock)

        if let waiter {
            if let error {
                waiter.resume(throwing: error)
            } else {
                waiter.resume(returning: nil)
            }
        }
    }

    func cancel() {
        os_unfair_lock_lock(lock)
        guard !didFinish else {
            os_unfair_lock_unlock(lock)
            return
        }
        didFinish = true
        terminalError = CancellationError()
        let waiter = self.waiter
        let onCancel = self.onCancel
        self.waiter = nil
        self.onStart = nil
        self.onCancel = nil
        os_unfair_lock_unlock(lock)

        onCancel?()
        waiter?.resume(throwing: CancellationError())
    }

    private func prepareNext(_ continuation: CheckedContinuation<Element?, any Error>) -> (@Sendable () -> Void)? {
        os_unfair_lock_lock(lock)
        let start: (@Sendable () -> Void)?
        if didStart {
            start = nil
        } else {
            didStart = true
            start = onStart
        }

        if !buffered.isEmpty {
            let value = buffered.removeFirst()
            bufferedBytes -= cost(value)
            os_unfair_lock_unlock(lock)
            continuation.resume(returning: value)
            return start
        }
        if didFinish {
            let error = terminalError
            os_unfair_lock_unlock(lock)
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: nil)
            }
            return start
        }

        waiter = continuation
        os_unfair_lock_unlock(lock)
        return start
    }

    private struct CancellationHandler: Sendable {
        weak var emitter: TerminalStreamEmitter?

        func cancel() {
            emitter?.cancel()
        }
    }
}

/// A lazy terminal stream returned by `Call.streamBytes()` and `Call.streamStrings()`.
///
/// The request starts on first iteration. Dropping the iterator early, such as
/// by `break` from a `for await` loop, cancels the underlying request so long
/// lived streams do not keep downloading into Iris's buffer.
public struct IrisStream<Element: Sendable>: AsyncSequence, Sendable {
    public typealias AsyncIterator = Iterator

    private let emitter: TerminalStreamEmitter<Element>

    fileprivate init(emitter: TerminalStreamEmitter<Element>) {
        self.emitter = emitter
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(emitter: emitter)
    }

    public struct Iterator: AsyncIteratorProtocol {
        private let state: IteratorState

        fileprivate init(emitter: TerminalStreamEmitter<Element>) {
            state = IteratorState(emitter: emitter)
        }

        public mutating func next() async throws -> Element? {
            try await state.next()
        }
    }

    private final class IteratorState: @unchecked Sendable {
        private let emitter: TerminalStreamEmitter<Element>
        private let lock: os_unfair_lock_t
        private var isFinished = false

        init(emitter: TerminalStreamEmitter<Element>) {
            self.emitter = emitter
            lock = .allocate(capacity: 1)
            lock.initialize(to: os_unfair_lock_s())
        }

        deinit {
            os_unfair_lock_lock(lock)
            let shouldCancel = !isFinished
            os_unfair_lock_unlock(lock)
            if shouldCancel {
                emitter.cancel()
            }
            lock.deinitialize(count: 1)
            lock.deallocate()
        }

        func next() async throws -> Element? {
            do {
                let value = try await emitter.next()
                if value == nil {
                    markFinished()
                }
                return value
            } catch {
                markFinished()
                throw error
            }
        }

        private func markFinished() {
            os_unfair_lock_lock(lock)
            isFinished = true
            os_unfair_lock_unlock(lock)
        }
    }
}

/// Stores cancellation hooks for a lazily-started terminal stream.
private final class TerminalStreamCancellation: @unchecked Sendable {
    private let lock: os_unfair_lock_t
    private var isCancelled = false
    private var task: Task<Void, Never>?
    private var token: AlamofireRequestCancellationToken?

    init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock_s())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    func set(task: Task<Void, Never>, token: AlamofireRequestCancellationToken) {
        os_unfair_lock_lock(lock)
        if isCancelled {
            os_unfair_lock_unlock(lock)
            task.cancel()
            token.cancel()
            return
        }
        self.task = task
        self.token = token
        os_unfair_lock_unlock(lock)
    }

    func cancel() {
        os_unfair_lock_lock(lock)
        isCancelled = true
        let task = self.task
        let token = self.token
        os_unfair_lock_unlock(lock)

        task?.cancel()
        token?.cancel()
    }
}

/// Network-layer outcome plus session metrics. Plugins still see only `result`.
///
/// `@unchecked Sendable` is valid because `URLSessionTaskMetrics` is an
/// immutable snapshot published after the task finishes.
struct NetworkDelivery: @unchecked Sendable {
    let result: Result<HTTPResponse, IrisError>
    let metrics: URLSessionTaskMetrics?

    init(result: Result<HTTPResponse, IrisError>, metrics: URLSessionTaskMetrics? = nil) {
        self.result = result
        self.metrics = metrics
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
        try await request.resolvedClient.send(request)
    }

    static func send<Model: Decodable>(_ request: Call<Model>, using client: IrisClient) async throws -> Response<Model> {
        let broadcaster = EventBroadcaster(from: request)
        let cancellationToken = AlamofireRequestCancellationToken()
        return try await withTaskCancellationHandler {
            defer { broadcaster.finish() }
            return try await execute(request, broadcaster: broadcaster, cancellationToken: cancellationToken, client: client)
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
        _ body: @Sendable (CallSession<Model>) async throws -> Void
    ) async throws -> Response<Model> {
        try await request.resolvedClient.send(request, body)
    }

    static func send<Model: Decodable>(
        _ request: Call<Model>,
        _ body: @Sendable (CallSession<Model>) async throws -> Void,
        using client: IrisClient
    ) async throws -> Response<Model> {
        let broadcaster = EventBroadcaster(from: request)
        let cancellationToken = AlamofireRequestCancellationToken()
        let sendableRequest = UncheckedSendable(value: request)
        
        let valueTask = Task<Response<Model>, Error> {
            defer { broadcaster.finish() }
            return try await execute(sendableRequest.value, broadcaster: broadcaster, cancellationToken: cancellationToken, client: client)
        }
        
        let session = CallSession(valueTask: valueTask, broadcaster: broadcaster)
        
        return try await withTaskCancellationHandler {
            do {
                try await body(session)
                return try await valueTask.value
            } catch {
                valueTask.cancel()
                cancellationToken.cancel()
                broadcaster.finish()
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
        try await request.resolvedClient.fetch(request)
    }

    /// Streams response body bytes without accumulating them into a final response.
    ///
    /// This is a lazy terminal API, similar to Alamofire's `responseStream`:
    /// the request starts when the returned sequence is first iterated.
    public static func streamBytes<Model: Decodable>(_ request: Call<Model>) -> IrisStream<Data> {
        request.resolvedClient.streamBytes(request)
    }

    static func streamBytes<Model: Decodable>(
        _ request: Call<Model>,
        using client: IrisClient
    ) -> IrisStream<Data> {
        makeByteTerminalStream(request, using: client)
    }

    /// Streams response body text chunks without accumulating them into a final response.
    ///
    /// This is a lazy terminal API, similar to Alamofire's `responseStreamString`:
    /// the request starts when the returned sequence is first iterated.
    public static func streamStrings<Model: Decodable>(_ request: Call<Model>) -> IrisStream<String> {
        request.resolvedClient.streamStrings(request)
    }

    static func streamStrings<Model: Decodable>(
        _ request: Call<Model>,
        using client: IrisClient
    ) -> IrisStream<String> {
        makeStringTerminalStream(request, using: client)
    }
    
    // MARK: - Private Methods

    private static func makeByteTerminalStream<Model: Decodable>(
        _ request: Call<Model>,
        using client: IrisClient
    ) -> IrisStream<Data> {
        let emitter = TerminalStreamEmitter<Data>(cost: { $0.count })
        let sendableRequest = UncheckedSendable(value: request)
        emitter.setStart { [weak emitter] in
            guard let emitter else { return }
            guard emitter.shouldStartRequest else { return }
            let cancellation = TerminalStreamCancellation()
            let cancellationToken = AlamofireRequestCancellationToken()
            emitter.setCancel { cancellation.cancel() }
            let streamTask = Task {
                await runByteTerminalStream(
                    sendableRequest.value,
                    using: client,
                    cancellationToken: cancellationToken,
                    yield: { emitter.yield($0) },
                    finish: { emitter.finish(throwing: $0) }
                )
            }
            cancellation.set(task: streamTask, token: cancellationToken)
        }
        return IrisStream(emitter: emitter)
    }

    private static func makeStringTerminalStream<Model: Decodable>(
        _ request: Call<Model>,
        using client: IrisClient
    ) -> IrisStream<String> {
        let emitter = TerminalStreamEmitter<String>(cost: { $0.utf8.count })
        let sendableRequest = UncheckedSendable(value: request)
        emitter.setStart { [weak emitter] in
            guard let emitter else { return }
            guard emitter.shouldStartRequest else { return }
            let cancellation = TerminalStreamCancellation()
            let cancellationToken = AlamofireRequestCancellationToken()
            emitter.setCancel { cancellation.cancel() }
            let streamTask = Task {
                await runStringTerminalStream(
                    sendableRequest.value,
                    using: client,
                    cancellationToken: cancellationToken,
                    yield: { emitter.yield($0) },
                    finish: { emitter.finish(throwing: $0) }
                )
            }
            cancellation.set(task: streamTask, token: cancellationToken)
        }
        return IrisStream(emitter: emitter)
    }

    private static func runByteTerminalStream<Model: Decodable>(
        _ request: Call<Model>,
        using client: IrisClient,
        cancellationToken: AlamofireRequestCancellationToken,
        yield: @escaping @Sendable (Data) -> Void,
        finish: @escaping @Sendable ((any Error)?) -> Void
    ) async {
        do {
            let configuration = client.configuration
            let stubBehavior = request.stubBehavior ?? configuration.stubBehavior
            if let stubBehavior {
                try await performStubTerminalStream(
                    request,
                    behavior: stubBehavior,
                    configuration: configuration,
                    yield: yield
                )
                finish(nil)
                return
            }

            try await performLiveByteTerminalStream(
                request,
                configuration: configuration,
                cancellationToken: cancellationToken,
                yield: yield
            )
            finish(nil)
        } catch {
            finish(error)
        }
    }

    private static func runStringTerminalStream<Model: Decodable>(
        _ request: Call<Model>,
        using client: IrisClient,
        cancellationToken: AlamofireRequestCancellationToken,
        yield: @escaping @Sendable (String) -> Void,
        finish: @escaping @Sendable ((any Error)?) -> Void
    ) async {
        do {
            let configuration = client.configuration
            let stubBehavior = request.stubBehavior ?? configuration.stubBehavior
            if let stubBehavior {
                try await performStubTerminalStream(
                    request,
                    behavior: stubBehavior,
                    configuration: configuration,
                    yield: { data in
                        if let string = String(data: data, encoding: .utf8) {
                            yield(string)
                        }
                    }
                )
                finish(nil)
                return
            }

            try await performLiveStringTerminalStream(
                request,
                configuration: configuration,
                cancellationToken: cancellationToken,
                yield: yield
            )
            finish(nil)
        } catch {
            finish(error)
        }
    }

    private static func sleepForStubDelay(_ interval: TimeInterval) async throws {
        guard interval.isFinite, interval > 0 else {
            return
        }

        let maximumSeconds = Double(UInt64.max) / 1_000_000_000
        let clampedInterval = min(interval, maximumSeconds)
        try await _Concurrency.Task.sleep(nanoseconds: UInt64(clampedInterval * 1_000_000_000))
    }
    
    /// Stub or live request. Shared by `send()` and `send { session in }` so the
    /// session path can start this work in a sibling task without changing
    /// plugin / sidecar / decode order.
    private static func execute<Model: Decodable>(
        _ request: Call<Model>,
        broadcaster: EventBroadcaster,
        cancellationToken: AlamofireRequestCancellationToken,
        client: IrisClient
    ) async throws -> Response<Model> {
        // Snapshot the client configuration once so a concurrent configure
        // cannot hand this request a mix of old and new values mid-flight.
        let configuration = client.configuration
        let startedAt = CFAbsoluteTimeGetCurrent()
        let stubBehavior = request.stubBehavior ?? configuration.stubBehavior
        if let stubBehavior {
            return try await performStub(request, behavior: stubBehavior, broadcaster: broadcaster, configuration: configuration, startedAt: startedAt)
        }
        return try await performRequest(request, broadcaster: broadcaster, cancellationToken: cancellationToken, configuration: configuration, startedAt: startedAt)
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
        configuration: IrisConfiguration,
        startedAt: CFAbsoluteTime
    ) async throws -> Response<Model> {
        var requestWithResolvedRetry = request
        requestWithResolvedRetry.retryPolicy = requestWithResolvedRetry.retryPolicy(over: configuration)
        let resolvedRequest = requestWithResolvedRetry
        let urlRequest = try makeURLRequest(from: resolvedRequest, configuration: configuration)
        
        // 4. Create interceptor (bridges Plugin system to Alamofire)
        // Capture plugins array to satisfy Sendable requirement
        let plugins = configuration.plugins
        let sendableResolvedRequest = UncheckedSendable(value: resolvedRequest)
        let interceptor = IrisCallInterceptor(
            prepare: { @Sendable urlRequest in
                try await prepare(urlRequest, target: sendableResolvedRequest.value, plugins: plugins)
            },
            retryPolicy: resolvedRequest.retryPolicy,
            streamHasDeliveredChunks: { broadcaster.hasYieldedChunks }
        )
        
        // 5. Execute request based on task type. Network methods return Result
        // so failures still flow through plugin didReceive/process.
        let session = configuration.session
        let delivery: NetworkDelivery
        
        switch resolvedRequest.task {
        case .uploadFile(let fileURL):
            delivery = await performUploadFile(urlRequest, fileURL: fileURL, interceptor: interceptor, session: session, request: resolvedRequest, plugins: plugins, broadcaster: broadcaster, cancellationToken: cancellationToken)
            
        case .uploadMultipartFormData(let formData):
            delivery = await performUploadMultipart(urlRequest, formData: formData, interceptor: interceptor, session: session, request: resolvedRequest, plugins: plugins, broadcaster: broadcaster, cancellationToken: cancellationToken)
            
        case .uploadCompositeMultipartFormData(let formData, _):
            delivery = await performUploadMultipart(urlRequest, formData: formData, interceptor: interceptor, session: session, request: resolvedRequest, plugins: plugins, broadcaster: broadcaster, cancellationToken: cancellationToken)
            
        case .downloadDestination(let destination):
            delivery = await performDownload(urlRequest, destination: destination, interceptor: interceptor, session: session, request: resolvedRequest, plugins: plugins, broadcaster: broadcaster, cancellationToken: cancellationToken)
            
        case .downloadParameters(_, _, let destination):
            delivery = await performDownload(urlRequest, destination: destination, interceptor: interceptor, session: session, request: resolvedRequest, plugins: plugins, broadcaster: broadcaster, cancellationToken: cancellationToken)
            
        default:
            // Data tasks only. File upload/download ignore `stream()`.
            if resolvedRequest.isStream {
                delivery = await performStream(urlRequest, interceptor: interceptor, session: session, request: resolvedRequest, plugins: plugins, broadcaster: broadcaster, cancellationToken: cancellationToken)
            } else {
                delivery = await performDataRequest(urlRequest, interceptor: interceptor, session: session, request: resolvedRequest, plugins: plugins, broadcaster: broadcaster, cancellationToken: cancellationToken)
            }
        }
        
        // 6-8. Restore the user's success definition, then notify plugins,
        // process, and decode or throw.
        let remapped = RetryPolicy.restoreUserAcceptedStatus(delivery, validation: resolvedRequest.validationType)
        return try finish(remapped, request: resolvedRequest, configuration: configuration, startedAt: startedAt)
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
        let decoder = (customDecoder ?? configuration.jsonDecoder).irisCopy()
        
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
        _ delivery: NetworkDelivery,
        request: Call<Model>,
        configuration: IrisConfiguration,
        startedAt: CFAbsoluteTime
    ) throws -> Response<Model> {
        configuration.plugins.forEach { $0.didReceive(delivery.result, target: request) }
        
        var processedResult = delivery.result
        for plugin in configuration.plugins {
            processedResult = plugin.process(processedResult, target: request)
        }
        
        switch processedResult {
        case .success(let rawResponse):
            let decodeStartedAt = CFAbsoluteTimeGetCurrent()
            do {
                let model = try decodeModel(Model.self, from: rawResponse, using: request.decoder, configuration: configuration)
                let response = Response(model: model, httpResponse: rawResponse)
                notifyComplete(
                    request,
                    result: .success(response),
                    startedAt: startedAt,
                    serializationDuration: CFAbsoluteTimeGetCurrent() - decodeStartedAt,
                    metrics: delivery.metrics
                )
                return response
            } catch let error as IrisError {
                notifyComplete(
                    request,
                    result: .failure(error),
                    startedAt: startedAt,
                    serializationDuration: CFAbsoluteTimeGetCurrent() - decodeStartedAt,
                    metrics: delivery.metrics
                )
                throw error
            } catch {
                let irisError = IrisError.underlying(error, rawResponse)
                notifyComplete(
                    request,
                    result: .failure(irisError),
                    startedAt: startedAt,
                    serializationDuration: CFAbsoluteTimeGetCurrent() - decodeStartedAt,
                    metrics: delivery.metrics
                )
                throw error
            }
        case .failure(let error):
            notifyComplete(
                request,
                result: .failure(error),
                startedAt: startedAt,
                serializationDuration: 0,
                metrics: delivery.metrics
            )
            throw error
        }
    }

    /// Applies plugin request preparation in registration order.
    private static func prepare<Model: Decodable>(
        _ urlRequest: URLRequest,
        target request: Call<Model>,
        plugins: [any PluginType]
    ) async throws -> URLRequest {
        var prepared = urlRequest
        for plugin in plugins {
            prepared = try await plugin.prepare(prepared, target: request)
        }
        return prepared
    }

    private static func performLiveByteTerminalStream<Model: Decodable>(
        _ request: Call<Model>,
        configuration: IrisConfiguration,
        cancellationToken: AlamofireRequestCancellationToken,
        yield: @escaping @Sendable (Data) -> Void
    ) async throws {
        var requestWithResolvedRetry = request
        requestWithResolvedRetry.retryPolicy = requestWithResolvedRetry.retryPolicy(over: configuration)
        let resolvedRequest = requestWithResolvedRetry
        let urlRequest = try makeURLRequest(from: resolvedRequest, configuration: configuration)
        let plugins = configuration.plugins
        let streamState = TerminalStreamCompletion()
        let sendableResolvedRequest = UncheckedSendable(value: resolvedRequest)
        let interceptor = IrisCallInterceptor(
            prepare: { @Sendable urlRequest in
                try await prepare(urlRequest, target: sendableResolvedRequest.value, plugins: plugins)
            },
            retryPolicy: resolvedRequest.retryPolicy,
            streamHasDeliveredChunks: { streamState.hasYieldedChunks }
        )

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (requestCompletion: CheckedContinuation<Void, any Error>) in
                let completion = streamState
                let validationCodes = RetryPolicy.acceptableStatusCodes(
                    for: resolvedRequest.validationType,
                    policy: resolvedRequest.retryPolicy
                )
                let streamRequest = configuration.session.requestQueue.sync {
                    var streamRequest = configuration.session.streamRequest(
                        urlRequest,
                        automaticallyCancelOnStreamError: false,
                        interceptor: interceptor
                    )
                    if let validationCodes {
                        streamRequest = streamRequest.validate(statusCode: validationCodes)
                    }
                    configureWillSend(streamRequest, interceptor: interceptor, request: resolvedRequest, plugins: plugins)
                    return streamRequest
                }
                cancellationToken.setRequest(streamRequest)

                streamRequest.responseStream(on: resolvedRequest.chunkQueue) { stream in
                    switch stream.event {
                    case .stream(.success(let data)):
                        streamState.markYieldedChunk()
                        yield(data)
                    case .complete(let streamCompletion):
                        let delivery = terminalDelivery(
                            data: Data(),
                            request: streamCompletion.request,
                            response: streamCompletion.response,
                            error: streamCompletion.error,
                            metrics: streamRequest.metrics,
                            validation: resolvedRequest.validationType
                        )
                        completeTerminalStream(
                            delivery,
                            request: resolvedRequest,
                            plugins: plugins,
                            completion: completion,
                            continuation: requestCompletion
                        )
                    }
                }
            }
        } onCancel: {
            cancellationToken.cancel()
        }
    }

    private static func performLiveStringTerminalStream<Model: Decodable>(
        _ request: Call<Model>,
        configuration: IrisConfiguration,
        cancellationToken: AlamofireRequestCancellationToken,
        yield: @escaping @Sendable (String) -> Void
    ) async throws {
        var requestWithResolvedRetry = request
        requestWithResolvedRetry.retryPolicy = requestWithResolvedRetry.retryPolicy(over: configuration)
        let resolvedRequest = requestWithResolvedRetry
        let urlRequest = try makeURLRequest(from: resolvedRequest, configuration: configuration)
        let plugins = configuration.plugins
        let streamState = TerminalStreamCompletion()
        let sendableResolvedRequest = UncheckedSendable(value: resolvedRequest)
        let interceptor = IrisCallInterceptor(
            prepare: { @Sendable urlRequest in
                try await prepare(urlRequest, target: sendableResolvedRequest.value, plugins: plugins)
            },
            retryPolicy: resolvedRequest.retryPolicy,
            streamHasDeliveredChunks: { streamState.hasYieldedChunks }
        )

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (requestCompletion: CheckedContinuation<Void, any Error>) in
                let completion = streamState
                let validationCodes = RetryPolicy.acceptableStatusCodes(
                    for: resolvedRequest.validationType,
                    policy: resolvedRequest.retryPolicy
                )
                let streamRequest = configuration.session.requestQueue.sync {
                    var streamRequest = configuration.session.streamRequest(
                        urlRequest,
                        automaticallyCancelOnStreamError: false,
                        interceptor: interceptor
                    )
                    if let validationCodes {
                        streamRequest = streamRequest.validate(statusCode: validationCodes)
                    }
                    configureWillSend(streamRequest, interceptor: interceptor, request: resolvedRequest, plugins: plugins)
                    return streamRequest
                }
                cancellationToken.setRequest(streamRequest)

                streamRequest.responseStreamString(on: resolvedRequest.chunkQueue) { stream in
                    switch stream.event {
                    case .stream(.success(let string)):
                        streamState.markYieldedChunk()
                        yield(string)
                    case .complete(let streamCompletion):
                        let delivery = terminalDelivery(
                            data: Data(),
                            request: streamCompletion.request,
                            response: streamCompletion.response,
                            error: streamCompletion.error,
                            metrics: streamRequest.metrics,
                            validation: resolvedRequest.validationType
                        )
                        completeTerminalStream(
                            delivery,
                            request: resolvedRequest,
                            plugins: plugins,
                            completion: completion,
                            continuation: requestCompletion
                        )
                    }
                }
            }
        } onCancel: {
            cancellationToken.cancel()
        }
    }

    private static func performStubTerminalStream<Model: Decodable>(
        _ request: Call<Model>,
        behavior: StubBehavior,
        configuration: IrisConfiguration,
        yield: @escaping @Sendable (Data) -> Void
    ) async throws {
        switch behavior {
        case .immediate:
            break
        case .delayed(let interval):
            try await sleepForStubDelay(interval)
        }

        let stubRequest: URLRequest?
        if let urlRequest = try? makeURLRequest(from: request, configuration: configuration) {
            stubRequest = try await prepare(urlRequest, target: request, plugins: configuration.plugins)
        } else {
            stubRequest = nil
        }
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

        if case .success = result {
            yield(stubData)
        }

        let processedResult = processTerminalResult(result, request: request, plugins: configuration.plugins)
        if case .failure(let error) = processedResult {
            throw error
        }
    }

    private static func terminalDelivery(
        data: Data,
        request: URLRequest?,
        response: HTTPURLResponse?,
        error: (any Error)?,
        metrics: URLSessionTaskMetrics?,
        validation: ValidationType
    ) -> NetworkDelivery {
        let result = mapNetworkResult(
            data: data,
            request: request,
            response: response,
            error: error
        )
        let delivery = NetworkDelivery(result: result, metrics: metrics)
        return RetryPolicy.restoreUserAcceptedStatus(delivery, validation: validation)
    }

    private static func completeTerminalStream<Model: Decodable>(
        _ delivery: NetworkDelivery,
        request: Call<Model>,
        plugins: [any PluginType],
        completion: TerminalStreamCompletion,
        continuation: CheckedContinuation<Void, any Error>
    ) {
        let processedResult = processTerminalResult(delivery.result, request: request, plugins: plugins)
        switch processedResult {
        case .success:
            completion.finish(continuation)
        case .failure(let error):
            completion.finish(continuation, throwing: error)
        }
    }

    private static func processTerminalResult<Model: Decodable>(
        _ result: Result<HTTPResponse, IrisError>,
        request: Call<Model>,
        plugins: [any PluginType]
    ) -> Result<HTTPResponse, IrisError> {
        plugins.forEach { $0.didReceive(result, target: request) }
        var processedResult = result
        for plugin in plugins {
            processedResult = plugin.process(processedResult, target: request)
        }
        return processedResult
    }

    private static func notifyComplete<Model: Decodable>(
        _ request: Call<Model>,
        result: Result<Response<Model>, IrisError>,
        startedAt: CFAbsoluteTime,
        serializationDuration: TimeInterval,
        metrics: URLSessionTaskMetrics?
    ) {
        guard let onCompleteHandler = request.onCompleteHandler else { return }
        onCompleteHandler(
            CompletionInfo(
                result: result,
                duration: CFAbsoluteTimeGetCurrent() - startedAt,
                serializationDuration: serializationDuration,
                metrics: metrics
            )
        )
    }
    
    /// Maps an Alamofire callback into a plugin-facing result.
    ///
    /// Validation failures become `.statusCode`. Transport failures remain
    /// `.underlying`, even if response headers were already received.
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
        
        if let afError = error.asAFError, afError.isResponseValidationError {
            return .failure(.statusCode(rawResponse))
        }
        return .failure(.underlying(error, response == nil ? nil : rawResponse))
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
    
    private static func mapDataResponse(_ afResponse: AFDataResponse<Data>) -> NetworkDelivery {
        let result: Result<HTTPResponse, IrisError>
        switch afResponse.result {
        case .success(let data):
            result = mapNetworkResult(
                data: data,
                request: afResponse.request,
                response: afResponse.response,
                error: nil
            )
        case .failure(let error):
            result = mapNetworkResult(
                data: afResponse.data ?? Data(),
                request: afResponse.request,
                response: afResponse.response,
                error: error
            )
        }
        return NetworkDelivery(result: result, metrics: afResponse.metrics)
    }
    
    private static func mapDownloadResponse(_ afResponse: DownloadResponse<Data, AFError>) -> NetworkDelivery {
        let result: Result<HTTPResponse, IrisError>
        switch afResponse.result {
        case .success(let data):
            result = mapNetworkResult(
                data: data,
                request: afResponse.request,
                response: afResponse.response,
                error: nil
            )
        case .failure(let error):
            result = mapNetworkResult(
                data: afResponse.resumeData ?? Data(),
                request: afResponse.request,
                response: afResponse.response,
                error: error
            )
        }
        return NetworkDelivery(result: result, metrics: afResponse.metrics)
    }
    
    private static func performDataResponseRequest<Model: Decodable>(
        request: Call<Model>,
        broadcaster: EventBroadcaster,
        cancellationToken: AlamofireRequestCancellationToken,
        buildRequest: () -> AFDataRequest
    ) async -> NetworkDelivery {
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let validationCodes = RetryPolicy.acceptableStatusCodes(
                    for: request.validationType,
                    policy: request.retryPolicy
                )
                var afRequest = buildRequest()
                
                if let validationCodes {
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
    ) async -> NetworkDelivery {
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let validationCodes = RetryPolicy.acceptableStatusCodes(
                    for: request.validationType,
                    policy: request.retryPolicy
                )
                var afRequest = buildRequest()
                
                if let validationCodes {
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
        plugins: [any PluginType]
    ) {
        interceptor.willSendHook.set { @Sendable [weak afRequest] urlRequest in
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
        plugins: [any PluginType],
        broadcaster: EventBroadcaster,
        cancellationToken: AlamofireRequestCancellationToken
    ) async -> NetworkDelivery {
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let accumulation = StreamAccumulation()
                let validationCodes = RetryPolicy.acceptableStatusCodes(
                    for: request.validationType,
                    policy: request.retryPolicy
                )
                let userValidationCodes = request.validationType.statusCodes
                let streamRequest = session.requestQueue.sync {
                    var streamRequest = session.streamRequest(
                        urlRequest,
                        automaticallyCancelOnStreamError: false,
                        interceptor: interceptor
                    )
                    if let validationCodes {
                        streamRequest = streamRequest.validate(statusCode: validationCodes)
                    }
                    configureWillSend(streamRequest, interceptor: interceptor, request: request, plugins: plugins)
                    return streamRequest
                }
                attachSidecars(streamRequest, from: request, broadcaster: broadcaster)
                cancellationToken.setRequest(streamRequest)
                
                streamRequest.responseStream(on: request.chunkQueue) { stream in
                    switch stream.event {
                    case .stream(.success(let data)):
                        accumulation.append(data)
                        broadcaster.yieldChunk(data, handlerOnQueue: true)
                    case .complete(let completion):
                        let data = accumulation.snapshot()
                        let metrics = streamRequest.metrics
                        if let error = completion.error {
                            accumulation.complete(
                                NetworkDelivery(
                                    result: mapNetworkResult(
                                        data: data,
                                        request: completion.request,
                                        response: completion.response,
                                        error: error
                                    ),
                                    metrics: metrics
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
                            let result: Result<HTTPResponse, IrisError>
                            if !userValidationCodes.isEmpty && !userValidationCodes.contains(httpResponse.statusCode) {
                                result = .failure(.statusCode(httpResponse))
                            } else {
                                result = .success(httpResponse)
                            }
                            accumulation.complete(
                                NetworkDelivery(result: result, metrics: metrics),
                                continuation: continuation
                            )
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
        var urlRequest = try endpoint.urlRequest(encoder: configuration.requestJSONEncoder)
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
        plugins: [any PluginType],
        broadcaster: EventBroadcaster,
        cancellationToken: AlamofireRequestCancellationToken
    ) async -> NetworkDelivery {
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
        plugins: [any PluginType],
        broadcaster: EventBroadcaster,
        cancellationToken: AlamofireRequestCancellationToken
    ) async -> NetworkDelivery {
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
        plugins: [any PluginType],
        broadcaster: EventBroadcaster,
        cancellationToken: AlamofireRequestCancellationToken
    ) async -> NetworkDelivery {
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
        plugins: [any PluginType],
        broadcaster: EventBroadcaster,
        cancellationToken: AlamofireRequestCancellationToken
    ) async -> NetworkDelivery {
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
        configuration: IrisConfiguration,
        startedAt: CFAbsoluteTime
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
            try await sleepForStubDelay(delay)
        }
        
        let stubRequest: URLRequest?
        if let urlRequest = try? makeURLRequest(from: request, configuration: configuration) {
            stubRequest = try await prepare(urlRequest, target: request, plugins: configuration.plugins)
        } else {
            stubRequest = nil
        }
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
        return try finish(
            NetworkDelivery(result: result),
            request: request,
            configuration: configuration,
            startedAt: startedAt
        )
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
