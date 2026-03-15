import AppIntents

struct TogglePlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Переключить воспроизведение"

    @MainActor
    func perform() async throws -> some IntentResult {
        ATPlayerViewModel.shared?.togglePlayback()
        return .result()
    }
}

struct NextTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Следующий трек"

    @MainActor
    func perform() async throws -> some IntentResult {
        ATPlayerViewModel.shared?.playNext()
        return .result()
    }
}

struct PreviousTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Предыдущий трек"

    @MainActor
    func perform() async throws -> some IntentResult {
        ATPlayerViewModel.shared?.playPrevious()
        return .result()
    }
}
