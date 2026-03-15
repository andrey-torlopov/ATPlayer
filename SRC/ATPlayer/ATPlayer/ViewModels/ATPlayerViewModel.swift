import ActivityKit
import AVFoundation
import Combine
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class ATPlayerViewModel: ObservableObject {
    static weak var shared: ATPlayerViewModel?

    @Published var sections: [PlaylistSection] = []
    @Published var selectedTrackID: UUID?
    @Published var showImporter = false
    @Published var showSettings = false
    @Published var nowPlayingTitle = "READY"
    @Published var nowPlayingArtwork: Data?
    @Published var importError: String?
    @Published var importTargetSection: PlaylistSection?

    let supportedTypes: [UTType] = [.mp3, .mpeg4Audio, .audio, .folder]
    let playbackService = AudioPlaybackService()
    let activityService = ATPlayerActivityService()
    private let storageService: PlaylistStorageService
    private var activeScopedURL: URL?
    private var activityUpdateCancellable: AnyCancellable?

    public init(context: ModelContext) {
        self.storageService = PlaylistStorageService(context: context)
        ATPlayerViewModel.shared = self
        // activityService.endAllStaleActivities()
        playbackService.onTrackFinished = { [weak self] in
            guard let self else { return }
            // self.activityService.endActivity()
            self.playNext()
        }
        // setupActivityUpdates()
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

    func renameSection(_ section: PlaylistSection, to name: String) {
        do {
            try storageService.renameSection(section, to: name)
            reloadSections()
        } catch {
            importError = "Не удалось переименовать секцию: \(error.localizedDescription)"
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
                await importURLs(urls, to: section)
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

        if playbackService.duration > 0 {
            playbackService.play()
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
                nowPlayingArtwork = track.artwork
                importError = nil

                activityService.startOrUpdateActivity(
                    trackTitle: track.title,
                    artistName: track.artist,
                    duration: track.duration,
                    currentTime: 0,
                    isPlaying: true
                )
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
                activityService.endActivity()
                nowPlayingTitle = "READY"
            }
            try storageService.removeTrack(track)
            reloadSections()
        } catch {
            importError = "Не удалось удалить трек: \(error.localizedDescription)"
        }
    }

    // MARK: - Export

    func exportPlaylistsJSON() -> Data {
        var result: [String: [[String: String]]] = [:]
        for section in sections {
            let tracks = storageService.sortedTracks(in: section).map { track in
                [
                    "author": track.artist,
                    "title": track.title,
                    "path": track.filePath
                ]
            }
            result[section.name] = tracks
        }
        let data = (try? JSONSerialization.data(
            withJSONObject: result,
            options: [.prettyPrinted, .sortedKeys]
        )) ?? Data()
        return data
    }

    // MARK: - Private

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "atplayer" else { return }
        switch url.host {
        case "previous":
            playPrevious()
        case "toggle":
            togglePlayback()
        case "next":
            playNext()
        default:
            break
        }
    }

    private func setupActivityUpdates() {
        activityUpdateCancellable = playbackService.$currentTime
            .combineLatest(playbackService.$isPlaying)
            .sink { [weak self] currentTime, isPlaying in
                guard let self else { return }
                guard let track = self.selectedTrack else { return }
                self.activityService.updateActivity(
                    trackTitle: track.title,
                    artistName: track.artist,
                    duration: self.playbackService.duration,
                    currentTime: currentTime,
                    isPlaying: isPlaying
                )
            }
    }

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

    private func importURLs(_ urls: [URL], to section: PlaylistSection) async {
        let fileManager = FileManager.default
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else {
                importError = "Нет доступа к \(url.lastPathComponent)"
                continue
            }

            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                let audioFiles = collectAudioFiles(in: url)
                for fileURL in audioFiles {
                    guard await downloadFromiCloud(fileURL) else { continue }
                    await importSingleTrack(at: fileURL, to: section)
                }
                url.stopAccessingSecurityScopedResource()
            } else {
                guard await downloadFromiCloud(url) else {
                    url.stopAccessingSecurityScopedResource()
                    continue
                }
                await importSingleTrack(at: url, to: section)
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    private func importSingleTrack(at url: URL, to section: PlaylistSection) async {
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
                artwork: metadata.artwork,
                to: section
            )
        } catch {
            importError = "Не удалось сохранить \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func isDownloaded(_ url: URL) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            let status = values.ubiquitousItemDownloadingStatus
            return status == .current || status == nil
        } catch {
            return FileManager.default.isReadableFile(atPath: url.path)
        }
    }

    private func downloadFromiCloud(_ url: URL) async -> Bool {
        guard !isDownloaded(url) else { return true }

        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            importError = "Ошибка загрузки \(url.lastPathComponent): \(error.localizedDescription)"
            return false
        }

        for _ in 0..<120 {
            try? await Task.sleep(for: .milliseconds(500))
            if isDownloaded(url) { return true }
        }

        importError = "Таймаут скачивания \(url.lastPathComponent) из iCloud"
        return false
    }

    private func extractMetadata(
        from asset: AVURLAsset,
        fallbackName: String
    ) async throws -> (title: String, artist: String, duration: Double, artwork: Data?) {
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
        let artworkItem = AVMetadataItem.metadataItems(
            from: metadataItems,
            filteredByIdentifier: .commonIdentifierArtwork
        ).first

        let title = (try await titleItem?.load(.stringValue)) ?? fallbackName
        let artist = (try await artistItem?.load(.stringValue)) ?? "Unknown Artist"
        let artwork = try await artworkItem?.load(.dataValue)

        return (title, artist, duration, artwork)
    }

    private let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "alac", "caf"]

    private func collectAudioFiles(in directoryURL: URL) -> [URL] {
        var result: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .ubiquitousItemDownloadingStatusKey],
            options: [.skipsHiddenFiles]
        ) else { return result }

        for case let fileURL as URL in enumerator {
            if audioExtensions.contains(fileURL.pathExtension.lowercased()) {
                result.append(fileURL)
            }
        }
        return result
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
