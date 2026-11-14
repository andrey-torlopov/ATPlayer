import UIKit

/// Acquired synchronously before an asynchronous system-presentation update.
/// Audio may stop immediately afterward, removing the app's background runtime.
@MainActor
final class PlaybackBackgroundTask {
    typealias ExpirationHandler = @MainActor @Sendable () -> Void

    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var didFinish = false
    private let end: @MainActor (UIBackgroundTaskIdentifier) -> Void

    convenience init(name: String) {
        self.init(
            begin: { expiration in
                UIApplication.shared.beginBackgroundTask(withName: name, expirationHandler: expiration)
            },
            end: { UIApplication.shared.endBackgroundTask($0) }
        )
    }

    init(
        begin: @MainActor (@escaping ExpirationHandler) -> UIBackgroundTaskIdentifier,
        end: @escaping @MainActor (UIBackgroundTaskIdentifier) -> Void
    ) {
        self.end = end
        identifier = begin { [weak self] in self?.finish() }
        // Also balance a task whose expiration handler ran before begin returned.
        if didFinish { finish() }
    }

    func finish() {
        didFinish = true
        guard identifier != .invalid else { return }
        let completedIdentifier = identifier
        identifier = .invalid
        end(completedIdentifier)
    }
}
