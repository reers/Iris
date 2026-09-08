//
//  CallSession.swift
//  Iris
//
//  Live execution scope for one in-flight Call. Not a recipe, and not stored on Call.
//

import Foundation
import os.lock

/// One in-flight request, valid only inside `send { session in }`.
///
/// Progress and chunks are sidecars on this session. `send` still returns
/// `Response` after `body` finishes. Alamofire progress and response serializers
/// are attached before the `send` body runs, so `for await` on a sidecar does not
/// deadlock.
///
/// Do not store this value. It exists so the live request does not leak out of
/// the `send` closure as a second execution type.
///
public struct CallSession<ResponseType: Decodable & Sendable>: Sendable {
    
    private let valueTask: Task<Response<ResponseType>, Error>
    private let broadcaster: EventBroadcaster
    
    init(valueTask: Task<Response<ResponseType>, Error>, broadcaster: EventBroadcaster) {
        self.valueTask = valueTask
        self.broadcaster = broadcaster
    }
    
    /// Decoded terminal result. Safe to await more than once; plugins and
    /// `onComplete` still run a single time inside this task.
    public var value: Response<ResponseType> {
        get async throws {
            try await valueTask.value
        }
    }
    
    /// Upload progress. Finishes when the request completes, fails, or is cancelled.
    ///
    /// Live-only: values emitted before the stream is created are not replayed.
    /// Access the stream at the start of the `send` body to observe the full
    /// sequence. Each delivered `Progress` is an immutable snapshot taken when
    /// the value was emitted.
    public var uploadProgress: AsyncStream<Progress> {
        broadcaster.uploadProgress
    }
    
    /// Download progress. Finishes when the request completes, fails, or is cancelled.
    ///
    /// Live-only: values emitted before the stream is created are not replayed.
    /// Access the stream at the start of the `send` body to observe the full
    /// sequence. Each delivered `Progress` is an immutable snapshot taken when
    /// the value was emitted.
    public var downloadProgress: AsyncStream<Progress> {
        broadcaster.downloadProgress
    }
    
    /// Body fragments for `stream()` data tasks. Empty and immediately finished
    /// when the request is not a stream. The concatenated body is still decoded
    /// as `value`.
    ///
    /// Live-only: chunks emitted before the stream is created are not replayed.
    /// Access the stream at the start of the `send` body to observe every chunk,
    /// or await `value` for the full body.
    public var chunks: AsyncStream<Data> {
        broadcaster.chunks
    }
}

/// Multicasts one Alamofire progress/chunk probe to recipe handlers and to
/// `CallSession` streams.
///
/// Alamofire keeps a single `uploadProgress` closure. This type is the Iris-side
/// broadcast so `onUploadProgress` and `for await session.uploadProgress` can
/// coexist.
///
/// Streams are live-only: values emitted before a stream is created are not
/// replayed. `Progress` values are snapshotted when yielded because Alamofire
/// mutates a single shared instance over the request's lifetime; delivering the
/// reference would hand out values that silently change after the fact.
/// `@unchecked Sendable` is valid because every mutable field is accessed only
/// while `lock` is held, and continuations are yielded or finished outside the
/// lock.
final class EventBroadcaster: @unchecked Sendable {
    
    private let lock: os_unfair_lock_t
    private var didFinish = false
    
    private var uploadSubscribers: [AsyncStream<Progress>.Continuation] = []
    private var downloadSubscribers: [AsyncStream<Progress>.Continuation] = []
    private var chunkSubscribers: [AsyncStream<Data>.Continuation] = []
    
    private let uploadHandler: (@Sendable (Progress) -> Void)?
    private let uploadQueue: DispatchQueue
    private let downloadHandler: (@Sendable (Progress) -> Void)?
    private let downloadQueue: DispatchQueue
    private let chunkHandler: (@Sendable (Data) -> Void)?
    private let chunkQueue: DispatchQueue
    private let isStream: Bool
    
    init<Model: Decodable & Sendable>(from request: Call<Model>) {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock_s())
        uploadHandler = request.uploadProgressHandler
        uploadQueue = request.uploadProgressQueue
        downloadHandler = request.downloadProgressHandler
        downloadQueue = request.downloadProgressQueue
        chunkHandler = request.chunkHandler
        chunkQueue = request.chunkQueue
        isStream = request.isStream
    }
    
    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }
    
    var uploadProgress: AsyncStream<Progress> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            os_unfair_lock_lock(self.lock)
            if self.didFinish {
                os_unfair_lock_unlock(self.lock)
                continuation.finish()
            } else {
                self.uploadSubscribers.append(continuation)
                os_unfair_lock_unlock(self.lock)
            }
        }
    }
    
    var downloadProgress: AsyncStream<Progress> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            os_unfair_lock_lock(self.lock)
            if self.didFinish {
                os_unfair_lock_unlock(self.lock)
                continuation.finish()
            } else {
                self.downloadSubscribers.append(continuation)
                os_unfair_lock_unlock(self.lock)
            }
        }
    }
    
    var chunks: AsyncStream<Data> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            os_unfair_lock_lock(self.lock)
            if self.didFinish {
                os_unfair_lock_unlock(self.lock)
                continuation.finish()
            } else {
                self.chunkSubscribers.append(continuation)
                os_unfair_lock_unlock(self.lock)
            }
        }
    }
    
    /// - Parameter handlerOnQueue: True when Alamofire already invoked this on
    ///   the handler's queue, so the recipe closure can run inline.
    func yieldUpload(_ progress: Progress, handlerOnQueue: Bool) {
        let snapshot = Self.snapshot(progress)
        os_unfair_lock_lock(lock)
        let subscribers = didFinish ? nil : uploadSubscribers
        os_unfair_lock_unlock(lock)
        notify(uploadHandler, queue: uploadQueue, handlerOnQueue: handlerOnQueue, value: snapshot)
        subscribers?.forEach { $0.yield(snapshot) }
    }
    
    func yieldDownload(_ progress: Progress, handlerOnQueue: Bool) {
        let snapshot = Self.snapshot(progress)
        os_unfair_lock_lock(lock)
        let subscribers = didFinish ? nil : downloadSubscribers
        os_unfair_lock_unlock(lock)
        notify(downloadHandler, queue: downloadQueue, handlerOnQueue: handlerOnQueue, value: snapshot)
        subscribers?.forEach { $0.yield(snapshot) }
    }
    
    func yieldChunk(_ data: Data, handlerOnQueue: Bool) {
        guard isStream else { return }
        os_unfair_lock_lock(lock)
        let subscribers = didFinish ? nil : chunkSubscribers
        os_unfair_lock_unlock(lock)
        notify(chunkHandler, queue: chunkQueue, handlerOnQueue: handlerOnQueue, value: data)
        subscribers?.forEach { $0.yield(data) }
    }
    
    /// Stub mode has no byte traffic. Emit a completed `Progress` and, for
    /// streams, one chunk of the sample body.
    func deliverStub(data: Data) {
        let progress = Progress(totalUnitCount: 1)
        progress.completedUnitCount = 1
        yieldUpload(progress, handlerOnQueue: false)
        yieldDownload(progress, handlerOnQueue: false)
        yieldChunk(data, handlerOnQueue: false)
    }
    
    func finish() {
        os_unfair_lock_lock(lock)
        let alreadyFinished = didFinish
        didFinish = true
        let upload = uploadSubscribers
        let download = downloadSubscribers
        let chunks = chunkSubscribers
        uploadSubscribers.removeAll()
        downloadSubscribers.removeAll()
        chunkSubscribers.removeAll()
        os_unfair_lock_unlock(lock)
        guard !alreadyFinished else { return }
        upload.forEach { $0.finish() }
        download.forEach { $0.finish() }
        chunks.forEach { $0.finish() }
    }
    
    /// Snapshots a `Progress` so later mutations of Alamofire's shared instance
    /// cannot leak into values already handed to handlers and subscribers.
    private static func snapshot(_ progress: Progress) -> Progress {
        let copy = Progress(totalUnitCount: progress.totalUnitCount)
        copy.completedUnitCount = progress.completedUnitCount
        return copy
    }
    
    private func notify<Element: Sendable>(
        _ handler: (@Sendable (Element) -> Void)?,
        queue: DispatchQueue,
        handlerOnQueue: Bool,
        value: Element
    ) {
        guard let handler else { return }
        if handlerOnQueue {
            handler(value)
        } else {
            invokeAsynchronously(queue) { handler(value) }
        }
    }
}

/// Schedules `work` on `queue` without blocking the caller.
func invokeAsynchronously(_ queue: DispatchQueue, _ work: @escaping @Sendable () -> Void) {
    queue.async(execute: work)
}
