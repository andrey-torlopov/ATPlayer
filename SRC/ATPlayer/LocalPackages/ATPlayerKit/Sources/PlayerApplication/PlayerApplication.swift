import AppLocalization
import FolderDomain
import FolderFeature
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
    private let folders: FolderBrowserViewModel
    private var libraryMode: LibraryMode = .playlists
    @Published private var isFolderPresentationActive = false

    public init() throws {
        container = try PlaylistStorageService.createContainer()
        let folderAccess = FolderAccessService()
        let player = ATPlayerViewModel(
            storage: PlaylistStorageService(context: container.mainContext),
            audio: AudioPlaybackService(),
            activity: ATPlayerActivityService(),
            nowPlaying: NowPlayingService(),
            mediaAccess: PlaylistMediaAccess(),
            folderAccess: folderAccess
        )
        self.player = player
        folders = FolderBrowserViewModel(
            store: FolderSourceStore(), access: folderAccess,
            onPlay: { [weak player] selection in
                Task { await player?.playFolder(source: selection.source, entries: selection.entries, selectedID: selection.selectedID) }
            },
            onRemoveSource: { [weak player] id in player?.removeFolderSource(id: id) }
        )
        PlaybackIntentBridge.application = self
    }

    deinit {
        // Capture only the dependency; the deinitializing application must not escape.
        let cleanup: @MainActor @Sendable () -> Void = { [player] in player.shutdown() }
        if Thread.isMainThread {
            MainActor.assumeIsolated { cleanup() }
        } else {
            Task { @MainActor in cleanup() }
        }
    }

    public func rootView() -> some View {
        PlayerView(
            viewModel: player,
            folderLibrary: AnyView(FolderBrowserView(model: folders) { [weak self] isPresented in
                guard self?.isFolderPresentationActive != isPresented else { return }
                self?.isFolderPresentationActive = isPresented
            }),
            isFolderPresentationActive: isFolderPresentationActive
        ) { [weak self] mode in
            guard let self else { return }
            self.libraryMode = mode
            if mode == .folders { self.folders.refresh() } else { self.folders.suspend() }
        }
        .modifier(PlaybackLanguageObserver { [weak self] in
            self?.player.refreshPlaybackPresentation()
        })
    }

    public func becameActive() {
        player.refreshPlaybackPresentation()
        if libraryMode == .folders { folders.refresh() }
    }

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
        var errorDescription: String? { L10n.text("Плеер недоступен. Откройте ATPlayer и выберите трек.") }
    }
}

@MainActor
private struct PlaybackLanguageObserver: ViewModifier {
    @AppStorage(L10n.languageKey) private var language = L10n.languageCode
    let onChange: @MainActor () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: language) { _, _ in onChange() }
    }
}
