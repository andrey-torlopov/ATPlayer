import Combine
import SwiftUI

/// Presentation-only state; it never owns or restarts the playback session.
@MainActor
final class PlayerPresentationState: ObservableObject {
    @Published private(set) var activePresentations = Set<UUID>()

    var hasPresentation: Bool { !activePresentations.isEmpty }

    func setPresented(_ isPresented: Bool, for owner: UUID) {
        if isPresented {
            guard !activePresentations.contains(owner) else { return }
            activePresentations.insert(owner)
        } else {
            guard activePresentations.contains(owner) else { return }
            activePresentations.remove(owner)
        }
    }
}

enum AmbientPreferences {
    static let keepsScreenAwakeKey = "ambientKeepsScreenAwake"
}

/// Retains new landscape errors while a browser or sheet prevents their presentation.
/// Existing portrait errors are never replayed just because the device rotates.
struct AmbientErrorQueue {
    private(set) var pendingMessage: String?

    mutating func record(_ message: String?, isLandscape: Bool) {
        pendingMessage = isLandscape ? message : nil
    }

    mutating func takePending(canPresent: Bool) -> String? {
        guard canPresent else { return nil }
        defer { pendingMessage = nil }
        return pendingMessage
    }

    mutating func leaveLandscape() { pendingMessage = nil }
}

private struct PlayerPresentationActivityKey: EnvironmentKey {
    static let defaultValue: (UUID, Bool) -> Void = { _, _ in }
}

extension EnvironmentValues {
    var playerPresentationActivity: (UUID, Bool) -> Void {
        get { self[PlayerPresentationActivityKey.self] }
        set { self[PlayerPresentationActivityKey.self] = newValue }
    }
}

private struct PlayerPresentationActivityModifier: ViewModifier {
    @Environment(\.playerPresentationActivity) private var report
    @State private var owner = UUID()
    let isPresented: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented, initial: true) { _, value in report(owner, value) }
            .onDisappear { report(owner, false) }
            .onAppear { report(owner, isPresented) }
    }
}

extension View {
    func tracksPlayerPresentation(_ isPresented: Bool) -> some View {
        modifier(PlayerPresentationActivityModifier(isPresented: isPresented))
    }
}
