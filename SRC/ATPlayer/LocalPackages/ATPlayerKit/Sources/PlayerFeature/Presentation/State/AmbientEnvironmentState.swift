import Combine
import Foundation

struct AmbientEnvironmentSnapshot: Equatable {
    let isLowPowerModeEnabled: Bool
    let thermalState: ProcessInfo.ThermalState
}

/// Notification delivery may originate off the main thread; publishing always uses the UI actor.
@MainActor
final class AmbientEnvironmentState: ObservableObject {
    @Published private var snapshot: AmbientEnvironmentSnapshot
    private let readSnapshot: @MainActor () -> AmbientEnvironmentSnapshot
    private var subscriptions: Set<AnyCancellable> = []

    var isLowPowerModeEnabled: Bool { snapshot.isLowPowerModeEnabled }
    var thermalState: ProcessInfo.ThermalState { snapshot.thermalState }

    convenience init() {
        self.init(notificationCenter: .default) {
            AmbientEnvironmentSnapshot(
                isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
                thermalState: ProcessInfo.processInfo.thermalState
            )
        }
    }

    init(notificationCenter: NotificationCenter,
         readSnapshot: @escaping @MainActor () -> AmbientEnvironmentSnapshot) {
        self.readSnapshot = readSnapshot
        snapshot = readSnapshot()

        Publishers.Merge(
            notificationCenter.publisher(for: .NSProcessInfoPowerStateDidChange),
            notificationCenter.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
        )
        .sink { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        .store(in: &subscriptions)
    }

    /// Also refresh when the scene becomes active after a suspension.
    func refresh() {
        let current = readSnapshot()
        guard current != snapshot else { return }
        snapshot = current
    }

    isolated deinit {
        subscriptions.forEach { $0.cancel() }
    }
}
