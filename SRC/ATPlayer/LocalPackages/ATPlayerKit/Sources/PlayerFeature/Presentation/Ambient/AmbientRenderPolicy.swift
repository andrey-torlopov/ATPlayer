import CoreGraphics
import Foundation

/// Presentation-only decisions. These inputs never mutate the audio session.
struct AmbientRenderPolicy: Equatable {
    let isVisible: Bool
    let isSceneActive: Bool
    let isPlaying: Bool
    let reduceMotion: Bool
    let isLowPowerModeEnabled: Bool
    let thermalState: ProcessInfo.ThermalState
    let keepsScreenAwake: Bool

    var isAnimating: Bool {
        isVisible && isSceneActive && isPlaying && !reduceMotion && !requiresCooling
    }

    var preferredFPS: Int { usesReducedQuality ? 15 : 30 }

    var resolutionScale: CGFloat { usesReducedQuality ? 0.35 : 0.5 }

    /// Reduced Motion changes decoration, not the user's request to keep music visible.
    var shouldKeepAwake: Bool {
        keepsScreenAwake && isVisible && isSceneActive && isPlaying
            && !isLowPowerModeEnabled && !requiresCooling
    }

    private var usesReducedQuality: Bool {
        isLowPowerModeEnabled || thermalState != .nominal
    }

    private var requiresCooling: Bool {
        switch thermalState {
        case .nominal, .fair:
            return false
        case .serious, .critical:
            return true
        @unknown default:
            return true
        }
    }
}

enum PlayerScreenMode: Equatable {
    case standard
    case ambient

    /// Call with the container's size before keyboard avoidance changes its contents.
    func updated(for size: CGSize) -> PlayerScreenMode {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return self }
        return size.width > size.height ? .ambient : .standard
    }
}

/// A UIKit-independent arbiter: one window cannot cancel another window's request.
struct AmbientIdleTimerRequests {
    private var owners: Set<UUID> = []

    var isRequested: Bool { !owners.isEmpty }

    /// Returns a new system value only when the aggregate request changes.
    mutating func setRequested(_ requested: Bool, for owner: UUID) -> Bool? {
        let previous = isRequested
        if requested {
            owners.insert(owner)
        } else {
            owners.remove(owner)
        }
        return isRequested == previous ? nil : isRequested
    }
}
