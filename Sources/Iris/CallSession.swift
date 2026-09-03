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
/// Progress and chunks are sidecars on this session. The terminal result is
/// `value`. Alamofire progress and response serializers are attached before the
/// `send` body runs, so `for await` on a sidecar then `await value` does not
/// deadlock.
///
/// Do not store this value. It exists so the live request does not leak out of
/// the `send` closure as a second execution type.
public struct CallSession<ResponseType: Decodable> {
    
    private let valueTask: Task<Response<ResponseType>, Error>
    private let fanout: SidecarFanout
    
    init(valueTask: Task<Response<ResponseType>, Error>, fanout: SidecarFanout) {
        self.valueTask = valueTask
        self.fanout = fanout
    }
    
    /// Decoded terminal result. Safe to await more than once; plugins and
    /// `onComplete` still run a single time inside this task.
    public var value: Response<ResponseType> {
        get async throws {
            try await valueTask.value
        }
    }
    
    /// Upload progress. Finishes when the request completes, fails, or is cancelled.
    public var uploadProgress: AsyncStream<Progress> {
        fanout.uploadProgress
    }
    
    /// Download progress. Finishes when the request completes, fails, or is cancelled.
    public var downloadProgress: AsyncStream<Progress> {
        fanout.downloadProgress
    }
    
    /// Body fragments for `stream()` data tasks. Empty and immediately finished
    /// when the request is not a stream. The concatenated body is still decoded
    /// as `value`.
    public var chunks: AsyncStream<Data> {
        fanout.chunks
    }
}

/// Multicasts one Alamofire progress/chunk probe to recipe handlers and to
/// `CallSession` streams.
///
/// Alamofire keeps a single `uploadProgress` closure. This type is the Iris-side
/// fan-out so `onUploadProgress` and `for await session.uploadProgress` can
/// coexist. `@unchecked Sendable` is valid because every mutable field is
/// accessed only while `lock` is held, and continuations are yielded or finished
/// outside the lock.
final class SidecarFanout: @unchecked Sendable {
    
    private let lock: os_unfair_lock_t
    private var didFinish = false
    
    private var uploadBuffer: [Progress] = []
    private var downloadBuffer: [Progress] = []
    private var chunkBuffer: [Data] = []
    
    private var uploadSubscribers: [AsyncStream<Progress>.Continuation] = []
    private var downloadSubscribers: [AsyncStream<Progress>.Continuation] = []
    private var chunkSubscribers: [AsyncStream<Data>.Continuation] = []
    
    private let uploadHandler: ((Progress) -> Void)?
    private let uploadQueue: DispatchQueue
    private let downloadHandler: ((Progress) -> Void)?
    private let downloadQueue: DispatchQueue
    private let chunkHandler: ((Data) -> Void)?
    private let chunkQueue: DispatchQueue
    private let isStream: Bool
    
    init<Model: Decodable>(from request: Call<Model>) {
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
            for item in self.uploadBuffer {
                continuation.yield(item)
            }
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
            for item in self.downloadBuffer {
                continuation.yield(item)
            }
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
            for item in self.chunkBuffer {
                continuation.yield(item)
            }
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
        let subscribers = appendAndCopy(
            buffer: { $0.uploadBuffer.append(progress) },
            subscribers: { $0.uploadSubscribers }
        )
        notify(uploadHandler, queue: uploadQueue, handlerOnQueue: handlerOnQueue, value: progress)
        subscribers?.forEach { $0.yield(progress) }
    }
    
    func yieldDownload(_ progress: Progress, handlerOnQueue: Bool) {
        let subscribers = appendAndCopy(
            buffer: { $0.downloadBuffer.append(progress) },
            subscribers: { $0.downloadSubscribers }
        )
        notify(downloadHandler, queue: downloadQueue, handlerOnQueue: handlerOnQueue, value: progress)
        subscribers?.forEach { $0.yield(progress) }
    }
    
    func yieldChunk(_ data: Data, handlerOnQueue: Bool) {
        guard isStream else { return }
        let subscribers = appendAndCopy(
            buffer: { $0.chunkBuffer.append(data) },
            subscribers: { $0.chunkSubscribers }
        )
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
    
    /// Returns current subscribers when the event was accepted, or `nil` if already finished.
    private func appendAndCopy<Element>(
        buffer: (SidecarFanout) -> Void,
        subscribers: (SidecarFanout) -> [AsyncStream<Element>.Continuation]
    ) -> [AsyncStream<Element>.Continuation]? {
        os_unfair_lock_lock(lock)
        if didFinish {
            os_unfair_lock_unlock(lock)
            return nil
        }
        buffer(self)
        let current = subscribers(self)
        os_unfair_lock_unlock(lock)
        return current
    }
    
    private func notify<Element>(
        _ handler: ((Element) -> Void)?,
        queue: DispatchQueue,
        handlerOnQueue: Bool,
        value: Element
    ) {
        guard let handler else { return }
        if handlerOnQueue {
            handler(value)
        } else {
            invokeSynchronously(queue) { handler(value) }
        }
    }
}

/// Runs `work` on `queue` and waits for it.
///
/// `DispatchQueue.main.sync` from the main thread deadlocks, so that case runs inline.
func invokeSynchronously(_ queue: DispatchQueue, _ work: () -> Void) {
    if Thread.isMainThread && queue === DispatchQueue.main {
        work()
    } else {
        queue.sync(execute: work)
    }
}
