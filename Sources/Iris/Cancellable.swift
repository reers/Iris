//
//  Cancellable.swift
//  Iris
//
//  Defines the protocol and implementations for request cancellation.
//  Based on Moya's Cancellable protocol.
//

import Foundation

/// Protocol for types that can be cancelled.
///
/// Types conforming to `Cancellable` represent ongoing operations
/// (typically network requests) that can be cancelled before completion.
///
/// Example:
/// ```swift
/// let cancellable = provider.request(.users) { result in
///     // Handle result
/// }
///
/// // Cancel the request if needed
/// if !cancellable.isCancelled {
///     cancellable.cancel()
/// }
/// ```
public protocol Cancellable: Sendable {

    /// A Boolean value indicating whether the operation has been cancelled.
    var isCancelled: Bool { get }

    /// Cancels the represented operation.
    ///
    /// After calling this method, `isCancelled` will return `true`.
    /// The actual effect of cancellation depends on the underlying implementation.
    func cancel()
}

// MARK: - CancellableWrapper

/// A wrapper that holds a reference to an inner cancellable.
///
/// This is useful when the actual cancellable isn't available at creation time
/// but will be assigned later.
internal final class CancellableWrapper: Cancellable, @unchecked Sendable {
    
    /// The wrapped cancellable object.
    internal var innerCancellable: Cancellable = SimpleCancellable()

    /// Whether the wrapped cancellable has been cancelled.
    var isCancelled: Bool { innerCancellable.isCancelled }

    /// Cancels the wrapped cancellable.
    internal func cancel() {
        innerCancellable.cancel()
    }
}

// MARK: - SimpleCancellable

/// A simple implementation of `Cancellable` that just tracks cancellation state.
///
/// This is used as a default implementation when no actual cancellation
/// action is needed.
internal final class SimpleCancellable: Cancellable, @unchecked Sendable {
    
    /// Whether this cancellable has been cancelled.
    var isCancelled = false
    
    /// Marks this cancellable as cancelled.
    func cancel() {
        isCancelled = true
    }
}
