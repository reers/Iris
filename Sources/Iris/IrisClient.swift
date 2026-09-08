//
//  IrisClient.swift
//  Iris
//
//  Instance-scoped execution context for Iris requests.
//

import Foundation
import os.lock

/// A request execution context with its own configuration and Alamofire session.
///
/// Use `IrisClient` when different parts of an app need isolated networking
/// configuration, such as different sessions, pinning, plugins, coders, or
/// stubbing defaults. Calls without an explicit client use `shared`.
public final class IrisClient: @unchecked Sendable {

    /// The default client used by `Call().send()` and `Iris.send(...)`.
    public static let shared = IrisClient()

    private let lock: os_unfair_lock_t
    private var configurationStorage: IrisConfiguration

    /// The configuration used by this client.
    ///
    /// Reads and writes are serialized. A request snapshots this value when it
    /// starts, so replacing it does not affect requests already in flight.
    public var configuration: IrisConfiguration {
        get {
            os_unfair_lock_lock(lock)
            defer { os_unfair_lock_unlock(lock) }
            return configurationStorage
        }
        set {
            os_unfair_lock_lock(lock)
            configurationStorage = newValue
            os_unfair_lock_unlock(lock)
        }
    }

    /// Creates a client with an isolated configuration.
    public init(configuration: IrisConfiguration = IrisConfiguration()) {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock_s())
        configurationStorage = configuration
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    /// Sends a request using this client's configuration.
    public func send<Model: Decodable & Sendable>(_ request: Call<Model>) async throws -> Response<Model> {
        try await Iris.send(request.bound(to: self), using: self)
    }

    /// Starts the request on this client, then runs `body` with a live session.
    public func send<Model: Decodable & Sendable>(
        _ request: Call<Model>,
        _ body: @Sendable (CallSession<Model>) async throws -> Void
    ) async throws -> Response<Model> {
        try await Iris.send(request.bound(to: self), body, using: self)
    }

    /// Sends a request using this client and returns only the decoded model.
    public func fetch<Model: Decodable & Sendable>(_ request: Call<Model>) async throws -> Model {
        let response = try await send(request)
        return response.model
    }

    /// Streams response body bytes using this client's configuration.
    public func streamBytes<Model: Decodable & Sendable>(_ request: Call<Model>) -> AsyncThrowingStream<Data, Error> {
        Iris.streamBytes(request.bound(to: self), using: self)
    }

    /// Streams response body text chunks using this client's configuration.
    public func streamStrings<Model: Decodable & Sendable>(_ request: Call<Model>) -> AsyncThrowingStream<String, Error> {
        Iris.streamStrings(request.bound(to: self), using: self)
    }
}
