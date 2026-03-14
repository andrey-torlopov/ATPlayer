import AVFoundation
import Combine
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class WinampViewModel: ObservableObject {
    @Published var tracks: [TrackItem] = []
    @Published var selectedTrackID: UUID?
    @Published var showImporter = false
    @Published var showEqualizerWindow = false
    @Published var playlistExpanded = false
    @Published var nowPlayingTitle = "WINAMP READY"
    @Published var importError: String?

    let supportedTypes: [UTType] = [.mp3, .mpeg4Audio, .audio]
    let playbackService = AudioPlaybackService()
    private let storageService: PlaylistStorageService
    private var activeScopedURL: URL?

    init(context: ModelContext) {
        self.storageService = PlaylistStorageService(context: context)
        reloadTracks()
    }

    deinit {
        activeScopedURL?.stopAccessingSecurityScopedResource()
    }

    func reloadTracks() {
        do {
            tracks = try storageService.fetchTracks()
            if selectedTrackID == nil {
                selectedTrackID = tracks.first?.id
            }
        } catch {
            importError = "Не удалось загрузить плейлист: \(error.localizedDescription)"
        }
    }

    func importFiles(_ result: Result<[URL], Error>) {
        switch result {
        case let .failure(error):
            importError = "Ошибка импорта: \(error.localizedDescription)"
        case let .success(urls):
            Task {
                for url in urls {
                    await importTrack(at: url)
                }
                reloadTracks()
            }
        }
    }

    func togglePlayback() {
        if playbackService.isPlaying {
            playbackService.pause()
            return
        }

        guard let track = selectedTrack else { return }
        Task {
            await play(track: track)
        }
    }

    func play(track: TrackItem) async {
        do {
            stopActiveScopedURLIfNeeded()
            let url = try resolvedURL(for: track)
            try playbackService.loadAndPlay(url: url)
            activeScopedURL = url
            selectedTrackID = track.id
            nowPlayingTitle = track.displayTitle.uppercased()
        } catch {
            importError = "Не удалось воспроизвести \(track.title): \(error.localizedDescription)"
        }
    }

    func playNext() {
        guard let index = selectedIndex else { return }
        let nextIndex = tracks.index(after: index)
        guard tracks.indices.contains(nextIndex) else { return }
        Task {
            await play(track: tracks[nextIndex])
        }
    }

    func playPrevious() {
        guard let index = selectedIndex else { return }
        let previousIndex = tracks.index(before: index)
        guard tracks.indices.contains(previousIndex) else { return }
        Task {
            await play(track: tracks[previousIndex])
        }
    }

    func removeSelectedTrack() {
        guard let track = selectedTrack else { return }
        do {
            try storageService.remove(track: track)
            reloadTracks()
            nowPlayingTitle = "TRACK REMOVED"
        } catch {
            importError = "Не удалось удалить трек: \(error.localizedDescription)"
        }
    }

    private func importTrack(at url: URL) async {
        guard url.startAccessingSecurityScopedResource() else {
            importError = "Нет доступа к \(url.lastPathComponent)"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let bookmark = try url.bookmarkData(options: .minimalBookmark)
            let asset = AVURLAsset(url: url)
            let metadata = try await extractMetadata(from: asset, fallbackName: url.deletingPathExtension().lastPathComponent)
            _ = try storageService.appendTrack(
                title: metadata.title,
                artist: metadata.artist,
                url: url,
                bookmark: bookmark,
                duration: metadata.duration
            )
        } catch {
            importError = "Не удалось сохранить \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func extractMetadata(from asset: AVURLAsset, fallbackName: String) async throws -> (title: String, artist: String, duration: Double) {
        let duration = try await asset.load(.duration).seconds
        let metadataItems = try await asset.load(.commonMetadata)

        let titleItem = AVMetadataItem.metadataItems(from: metadataItems, filteredByIdentifier: .commonIdentifierTitle).first
        let artistItem = AVMetadataItem.metadataItems(from: metadataItems, filteredByIdentifier: .commonIdentifierArtist).first
        let title = (try await titleItem?.load(.stringValue)) ?? fallbackName
        let artist = (try await artistItem?.load(.stringValue)) ?? "Unknown Artist"

        return (title, artist, duration)
    }

    private func resolvedURL(for track: TrackItem) throws -> URL {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: track.bookmark,
            bookmarkDataIsStale: &stale
        )
        if stale {
            throw CocoaError(.fileReadUnknown)
        }
        guard url.startAccessingSecurityScopedResource() else {
            throw CocoaError(.fileReadNoPermission)
        }
        return url
    }

    private func stopActiveScopedURLIfNeeded() {
        activeScopedURL?.stopAccessingSecurityScopedResource()
        activeScopedURL = nil
    }

    var selectedTrack: TrackItem? {
        guard let selectedTrackID else { return tracks.first }
        return tracks.first(where: { $0.id == selectedTrackID })
    }

    private var selectedIndex: Int? {
        guard let selectedTrackID else { return nil }
        return tracks.firstIndex(where: { $0.id == selectedTrackID })
    }
}
