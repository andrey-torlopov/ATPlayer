import CoreFoundation
import Foundation
import PlaybackDomain

@MainActor
struct RadioPreferences {
    static let effectIntensityKey = "atplayer.radio.effectIntensity"
    static let backgroundIntensityKey = "atplayer.radio.backgroundIntensity"
    static let legacyTransitionIntensityKey = "atplayer.radio.transitionIntensity"
    static let legacyProfileIDKey = "atplayer.radio.profileID"

    let defaults: UserDefaults

    func load() -> RadioSettings {
        RadioSettings(
            effectIntensity: readLevel(forKey: Self.effectIntensityKey),
            backgroundIntensity: defaults.object(forKey: Self.backgroundIntensityKey) == nil
                ? nil : readLevel(forKey: Self.backgroundIntensityKey)
        )
    }

    func save(_ settings: RadioSettings) {
        defaults.set(settings.effectIntensity, forKey: Self.effectIntensityKey)
        defaults.set(settings.backgroundIntensity, forKey: Self.backgroundIntensityKey)
        defaults.removeObject(forKey: Self.legacyTransitionIntensityKey)
        defaults.removeObject(forKey: Self.legacyProfileIDKey)
    }

    private func readLevel(forKey key: String) -> Int {
        // integer(forKey:) accepts strings and booleans. Those are not valid saved levels.
        guard let number = defaults.object(forKey: key) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return 0 }
        let value = number.doubleValue
        guard value.isFinite, value.rounded(.towardZero) == value else { return 0 }
        if value <= 0 { return 0 }
        if value >= 10 { return 10 }
        return Int(value)
    }
}
