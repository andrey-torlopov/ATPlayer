import Foundation
import FolderDomain

/// Bridges a blocking Foundation accessor to an async caller. Every mutable field is
/// protected by `lock`; NSFileCoordinator.cancel() is explicitly thread-safe. A timed-out
/// caller returns immediately, while the worker retains its scope and discards late files.
/// The bounded OperationQueues prevent unresponsive providers from spawning more workers.
final class FolderIORequest<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var failure: Error?
    private var completed = false
    private var coordinator: NSFileCoordinator?
    private var timeoutItem: DispatchWorkItem?
    private let discard: @Sendable (Value) -> Void
    private let finished: @Sendable () -> Void

    init(discard: @escaping @Sendable (Value) -> Void = { _ in },
         finished: @escaping @Sendable () -> Void = {}) {
        self.discard = discard
        self.finished = finished
    }

    func run(on queue: OperationQueue, timeout: TimeInterval,
             operation: @escaping @Sendable (FolderIORequest<Value>) throws -> Value) async throws -> Value {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let failure {
                    lock.unlock()
                    continuation.resume(throwing: failure)
                    // No worker was enqueued, but resource accounting still needs completion.
                    finished()
                    return
                }
                self.continuation = continuation
                let timeoutItem = DispatchWorkItem { [weak self] in
                    self?.cancel(with: FolderAccessError.timedOut)
                }
                self.timeoutItem = timeoutItem
                lock.unlock()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
                queue.addOperation { [self] in
                    let result = Result {
                        try checkCancellation()
                        return try operation(self)
                    }
                    finish(result)
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel(with error: Error = CancellationError()) {
        lock.lock()
        guard !completed, failure == nil else {
            lock.unlock()
            return
        }
        failure = error
        let continuation = self.continuation
        self.continuation = nil
        let coordinator = self.coordinator
        let timeoutItem = self.timeoutItem
        self.timeoutItem = nil
        lock.unlock()
        timeoutItem?.cancel()
        coordinator?.cancel()
        continuation?.resume(throwing: error)
    }

    func checkCancellation() throws {
        lock.lock()
        let error = failure
        lock.unlock()
        if let error { throw error }
    }

    func coordinate<T>(at url: URL, options: NSFileCoordinator.ReadingOptions,
                       accessor: (URL) throws -> T) throws -> T {
        try checkCancellation()
        let coordinator = NSFileCoordinator()
        lock.lock()
        self.coordinator = coordinator
        let cancelled = failure != nil
        lock.unlock()
        if cancelled { coordinator.cancel() }
        defer {
            lock.lock()
            self.coordinator = nil
            lock.unlock()
        }
        try checkCancellation()
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(readingItemAt: url, options: options, error: &coordinationError) { coordinatedURL in
            result = Result {
                try checkCancellation()
                return try accessor(coordinatedURL)
            }
        }
        try checkCancellation()
        if let coordinationError { throw coordinationError }
        guard let result else { throw FolderAccessError.unavailable }
        return try result.get()
    }

    private func finish(_ result: Result<Value, Error>) {
        lock.lock()
        let wasCancelled = failure != nil
        let continuation = self.continuation
        self.continuation = nil
        completed = true
        let timeoutItem = self.timeoutItem
        self.timeoutItem = nil
        lock.unlock()
        timeoutItem?.cancel()
        if wasCancelled {
            if case let .success(value) = result { discard(value) }
        } else {
            continuation?.resume(with: result)
        }
        finished()
    }
}
