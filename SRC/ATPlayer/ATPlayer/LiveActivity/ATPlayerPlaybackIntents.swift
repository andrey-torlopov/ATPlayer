import AppIntents

struct TogglePlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Переключить воспроизведение"

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let player = ATPlayerViewModel.shared else { throw PlaybackIntentError.unavailable }
        await player.performPlaybackCommand(.toggle)
        return .result()
    }
}

struct NextTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Следующий трек"

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let player = ATPlayerViewModel.shared else { throw PlaybackIntentError.unavailable }
        await player.performPlaybackCommand(.next)
        return .result()
    }
}

struct PreviousTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Предыдущий трек"

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let player = ATPlayerViewModel.shared else { throw PlaybackIntentError.unavailable }
        await player.performPlaybackCommand(.previous)
        return .result()
    }
}

private nonisolated enum PlaybackIntentError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Плеер недоступен. Откройте ATPlayer и выберите трек."
    }
}
