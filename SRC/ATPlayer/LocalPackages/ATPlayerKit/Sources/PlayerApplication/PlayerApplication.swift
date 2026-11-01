import Combine
import Foundation
import PlaybackDomain
import PlayerFeature
import PlayerInfrastructure
import SwiftData
import SwiftUI

/// Owns the process-wide playback session, including launches from audio intents.
@MainActor
public final class PlayerApplication: ObservableObject {
    private let container: ModelContainer
    private let player: ATPlayerViewModel

    public init() throws {
        container = try PlaylistStorageService.createContainer()
        player = ATPlayerViewModel(
            storage: PlaylistStorageService(context: container.mainContext),
            audio: AudioPlaybackService(),
            activity: ATPlayerActivityService(),
            nowPlaying: NowPlayingService(),
            mediaAccess: PlaylistMediaAccess()
        )
        PlaybackIntentBridge.application = self
    }

    public func rootView() -> some View { PlayerView(viewModel: player) }

    public func becameActive() { player.refreshPlaybackPresentation() }

    public func openURL(_ url: URL) {
        guard url.scheme == "atplayer" else { return }
        let command: PlaybackCommand
        switch url.host {
        case "previous": command = .previous
        case "toggle": command = .toggle
        case "next": command = .next
        default: return
        }
        Task { await player.performPlaybackCommand(command) }
    }

    fileprivate func perform(_ command: PlaybackCommand) async {
        await player.performPlaybackCommand(command)
    }
}

/// The sole process entry point for AppIntents; this does not expose feature state.
@MainActor
public enum PlaybackIntentBridge {
    fileprivate static weak var application: PlayerApplication?

    public enum Command { case toggle, next, previous }

    public static func perform(_ command: Command) async throws {
        guard let application else { throw IntentError.unavailable }
        switch command {
        case .toggle: await application.perform(.toggle)
        case .next: await application.perform(.next)
        case .previous: await application.perform(.previous)
        }
    }

    private enum IntentError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Плеер недоступен. Откройте ATPlayer и выберите трек." }
    }
}
