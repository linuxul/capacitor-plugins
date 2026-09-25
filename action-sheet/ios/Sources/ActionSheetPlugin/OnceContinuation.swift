import Foundation

/// Resumes a continuation exactly once, so that a method awaiting a UIKit callback can neither hang nor resume twice.
///
/// The first ``resume(returning:)`` answers and later ones are ignored. When the object is released without having
/// been resumed, it resumes with `fallback`: whatever held it, such as the actions of an alert that was dismissed
/// another way or never appeared, can no longer answer.
final class OnceContinuation<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    private let fallback: Value

    init(_ continuation: CheckedContinuation<Value, Never>, fallback: Value) {
        self.continuation = continuation
        self.fallback = fallback
    }

    deinit {
        continuation?.resume(returning: fallback)
    }

    /// Resumes with `value` unless the continuation has been resumed already. Returns false when it had been.
    @discardableResult
    func resume(returning value: Value) -> Bool {
        let pending: CheckedContinuation<Value, Never>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
        return pending != nil
    }
}
