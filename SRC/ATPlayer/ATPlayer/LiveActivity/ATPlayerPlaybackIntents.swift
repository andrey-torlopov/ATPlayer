import AppIntents
import PlayerApplication

struct TogglePlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Переключить воспроизведение"

    @MainActor
    func perform() async throws -> some IntentResult {
        try await PlaybackIntentBridge.perform(.toggle)
        return .result()
    }
}

struct NextTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Следующий трек"

    @MainActor
    func perform() async throws -> some IntentResult {
        try await PlaybackIntentBridge.perform(.next)
        return .result()
    }
}

struct PreviousTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Предыдущий трек"

    @MainActor
    func perform() async throws -> some IntentResult {
        try await PlaybackIntentBridge.perform(.previous)
        return .result()
    }
}
