import AppIntents

struct TogglePlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Переключить воспроизведение"

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct NextTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Следующий трек"

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct PreviousTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Предыдущий трек"

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
