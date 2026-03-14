import AVFoundation
import Combine
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class WinampViewModel: ObservableObject {
    @Published var sections: [PlaylistSection] = []
    @Published var selectedTrackID: UUID?
    @Published var showImporter = false
    @Published var showEqualizerWindow = false
    @Published var nowPlayingTitle = "READY"
    @Published var importError: String?
    @Published var importTargetSection: PlaylistSection?

    let supportedTypes: [UTType] = [.mp3, .mpeg4Audio, .audio]
    let playbackService = AudioPlaybackService()
    private let storageService: PlaylistStorageService
    private var activeScopedURL: URL?

    init(context: ModelContext) {
        self.storageService = PlaylistStorageService(context: context)
        playbackService.onTrackFinished = { [weak self] in
            guard let self else { return }
            self.playNext()
        }
        reloadSections()
    }

    deinit {
        activeScopedURL?.stopAccessingSecurityScopedResource()
    }

    func reloadSections() {
        do {
            _ = try storageService.ensureDefaultSection()
            sections = try storageService.fetchSections()
        } catch {
            importError = "Не удалось загрузить плейлист: \(error.localizedDescription)"
        }
    }

    var allTracks: [TrackItem] {
        sections.flatMap { storageService.sortedTracks(in: $0) }
    }

    func tracks(in section: PlaylistSection) -> [TrackItem] {
        storageService.sortedTracks(in: section)
    }

    // MARK: - Sections

    func addSection(name: String) {
        do {
            _ = try storageService.createSection(name: name)
            reloadSections()
        } catch {
            importError = "Не удалось создать секцию: \(error.localizedDescription)"
        }
    }

    func removeSection(_ section: PlaylistSection) {
        do {
            try storageService.removeSection(section)
            reloadSections()
        } catch {
            importError = "Не удалось удалить секцию: \(error.localizedDescription)"
        }
    }

    // MARK: - Import

    func requestImport(to section: PlaylistSection) {
        importTargetSection = section
        showImporter = true
    }

    func importFiles(_ result: Result<[URL], Error>) {
        switch result {
        case let .failure(error):
            importError = "Ошибка импорта: \(error.localizedDescription)"
        case let .success(urls):
            let targetSection = importTargetSection
            Task {
                guard let section = targetSection ?? sections.first else { return }
                for url in urls {
                    await importTrack(at: url, to: section)
                }
                reloadSections()
            }
        }
        importTargetSection = nil
    }

    // MARK: - Playback

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
        guard !track.isCorrupted else {
            playNextAfter(track: track)
            return
        }

        do {
            stopActiveScopedURLIfNeeded()
            let url = try resolvedURL(for: track)
            do {
                try playbackService.loadAndPlay(url: url)
                activeScopedURL = url
                selectedTrackID = track.id
                nowPlayingTitle = track.displayTitle.uppercased()
            } catch {
                markCorrupted(track)
                playNextAfter(track: track)
            }
        } catch {
            importError = "Нет доступа к \(track.title): \(error.localizedDescription)"
            selectedTrackID = track.id
        }
    }

    func playNext() {
        guard let current = selectedTrack else { return }
        let all = allTracks
        guard let index = all.firstIndex(where: { $0.id == current.id }) else { return }
        let nextIndex = all.index(after: index)
        guard all.indices.contains(nextIndex) else { return }
        Task {
            await play(track: all[nextIndex])
        }
    }

    func playPrevious() {
        guard let current = selectedTrack else { return }
        let all = allTracks
        guard let index = all.firstIndex(where: { $0.id == current.id }) else { return }
        let previousIndex = all.index(before: index)
        guard all.indices.contains(previousIndex) else { return }
        Task {
            await play(track: all[previousIndex])
        }
    }

    func seek(to time: TimeInterval) {
        playbackService.seek(to: time)
    }

    // MARK: - Remove

    func removeTrack(_ track: TrackItem) {
        do {
            if track.id == selectedTrackID {
                playbackService.stop()
                nowPlayingTitle = "READY"
            }
            try storageService.removeTrack(track)
            reloadSections()
        } catch {
            importError = "Не удалось удалить трек: \(error.localizedDescription)"
        }
    }

    // MARK: - Private

    private func playNextAfter(track: TrackItem) {
        let all = allTracks
        guard let index = all.firstIndex(where: { $0.id == track.id }) else { return }
        let nextIndex = all.index(after: index)
        guard all.indices.contains(nextIndex) else { return }
        Task {
            await play(track: all[nextIndex])
        }
    }

    private func markCorrupted(_ track: TrackItem) {
        do {
            try storageService.markCorrupted(track)
            reloadSections()
        } catch {
            importError = "Не удалось пометить трек: \(error.localizedDescription)"
        }
    }

    private func importTrack(at url: URL, to section: PlaylistSection) async {
        guard url.startAccessingSecurityScopedResource() else {
            importError = "Нет доступа к \(url.lastPathComponent)"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let bookmark = try url.bookmarkData(options: .minimalBookmark)
            let asset = AVURLAsset(url: url)
            let metadata = try await extractMetadata(
                from: asset,
                fallbackName: url.deletingPathExtension().lastPathComponent
            )
            _ = try storageService.appendTrack(
                title: metadata.title,
                artist: metadata.artist,
                url: url,
                bookmark: bookmark,
                duration: metadata.duration,
                to: section
            )
        } catch {
            importError = "Не удалось сохранить \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func extractMetadata(
        from asset: AVURLAsset,
        fallbackName: String
    ) async throws -> (title: String, artist: String, duration: Double) {
        let duration = try await asset.load(.duration).seconds
        let metadataItems = try await asset.load(.commonMetadata)

        let titleItem = AVMetadataItem.metadataItems(
            from: metadataItems,
            filteredByIdentifier: .commonIdentifierTitle
        ).first
        let artistItem = AVMetadataItem.metadataItems(
            from: metadataItems,
            filteredByIdentifier: .commonIdentifierArtist
        ).first
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
        guard let selectedTrackID else { return allTracks.first }
        return allTracks.first(where: { $0.id == selectedTrackID })
    }
}
