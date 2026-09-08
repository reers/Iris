//
//  UncheckedSendable.swift
//  Iris
//
//  Internal escape hatch for compatibility boundaries.
//

/// Wraps values that Iris moves through internal concurrency machinery without
/// requiring every user model type to be `Sendable`.
///
/// The wrapper must stay internal. Public API should express precise Sendable
/// requirements instead of exposing this escape hatch to callers.
struct UncheckedSendable<Value>: @unchecked Sendable {
    var value: Value
}
