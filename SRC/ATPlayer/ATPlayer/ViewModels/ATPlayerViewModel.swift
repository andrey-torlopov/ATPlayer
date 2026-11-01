import ActivityKit
import AVFoundation
import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
public final class ATPlayerViewModel: ObservableObject {
    static weak var shared: ATPlayerViewModel?

    @Published var sections: [PlaylistSection] = []
    @Published var selectedTrackID: UUID?
    @Published var showImporter = false
    @Published var showSettings = false
    @Published var nowPlayingTitle = "Готов к воспроизведению"
    @Published var nowPlayingArtwork: Data?
    @Published var importError: String?
    @Published var importTargetSection: PlaylistSection?
    @Published var lastPlayedSectionID: UUID?
    @Published private(set) var isImporting = false
    @Published private(set) var playbackMode: PlaybackMode = .off

    let supportedTypes: [UTType] = [.mp3, .mpeg4Audio, .audio, .folder]
    let playbackService = AudioPlaybackService()
    let activityService = ATPlayerActivityService()
    private let storageService: PlaylistStorageService
    private var activeScopedURL: URL?
    private var playbackPresentationCancellable: AnyCancellable?
    private var presentationUpdateScheduled = false
    private lazy var nowPlayingService = NowPlayingService { [weak self] command in
        Task { @MainActor [weak self] in
            await self?.performPlaybackCommand(command)
        }
    }
    private var playbackErrorCancellable: AnyCancellable?
    private var playbackRequestID = UUID()
    private var pendingPlaybackRequestID: UUID?
    private var importTask: Task<Void, Never>?
    private var playbackQueue = PlaybackQueue()
    private var playbackModeRevision: UInt = 0

    private enum PlaybackRequest {
        case selection(UUID)
        case adjacent(PlaybackQueue.Direction)
        case finished
    }

    // Files imported through a folder need the folder's access grant after relaunch.
    // The envelope lives in the existing Data attribute; legacy raw bookmarks still resolve.
    private struct TrackBookmark: Codable {
        var file: Data
        var directory: Data?
    }

    private static let cloudDownloadAttempts = 120
    private static let cloudDownloadPollInterval: Duration = .milliseconds(500)

    public init(context: ModelContext) {
        self.storageService = PlaylistStorageService(context: context)
        ATPlayerViewModel.shared = self
        if let savedMode = UserDefaults.standard.string(forKey: "playbackMode")
            .flatMap(PlaybackMode.init(rawValue:)) {
            playbackMode = savedMode
        } else {
            // Preserve preferences from the earlier two-button development build.
            let legacyRepeat = UserDefaults.standard.string(forKey: "playbackRepeatMode")
            if legacyRepeat == "one" {
                playbackMode = .repeatOne
            } else if UserDefaults.standard.bool(forKey: "playbackShuffleEnabled") {
                playbackMode = .shuffle
            } else if legacyRepeat == "playlist" {
                playbackMode = .repeatPlaylist
            }
            UserDefaults.standard.set(playbackMode.rawValue, forKey: "playbackMode")
        }
        if let savedID = UserDefaults.standard.string(forKey: "lastPlayedSectionID") {
            lastPlayedSectionID = UUID(uuidString: savedID)
        }
        activityService.endAllStaleActivities()
        playbackService.onTrackFinished = { [weak self] in
            self?.handleTrackFinished()
        }
        setupPlaybackPresentation()
        playbackErrorCancellable = playbackService.$playbackError
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.importError = message
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
            updatePlaybackQueue()
            schedulePlaybackPresentationUpdate()
        } catch {
            importError = "Не удалось загрузить плейлисты. Повторите попытку."
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
            importError = "Не удалось создать плейлист. Повторите попытку."
        }
    }

    func removeSection(_ section: PlaylistSection) {
        let sectionID = section.id
        let removesSelectedTrack = section.tracks.contains { $0.id == selectedTrackID }
        do {
            try storageService.removeSection(section)
            if removesSelectedTrack {
                resetPlayback()
            }
            if lastPlayedSectionID == sectionID {
                lastPlayedSectionID = nil
                UserDefaults.standard.removeObject(forKey: "lastPlayedSectionID")
            }
            reloadSections()
        } catch {
            importError = "Не удалось удалить плейлист. Повторите попытку."
        }
    }

    func renameSection(_ section: PlaylistSection, to name: String) {
        do {
            try storageService.renameSection(section, to: name)
            reloadSections()
        } catch {
            importError = "Не удалось переименовать плейлист. Повторите попытку."
        }
    }

    // MARK: - Import

    func requestImport(to section: PlaylistSection) {
        guard !isImporting else { return }
        importTargetSection = section
        showImporter = true
    }

    func importFiles(_ result: Result<[URL], Error>) {
        let targetSectionID = importTargetSection?.id ?? sections.first?.id
        importTargetSection = nil
        switch result {
        case let .failure(error):
            guard (error as? CocoaError)?.code != .userCancelled else { return }
            importError = "Не удалось открыть выбранные файлы. Повторите импорт."
        case let .success(urls):
            guard !isImporting, let targetSectionID, !urls.isEmpty else { return }
            isImporting = true
            importError = nil
            importTask = Task { [weak self] in
                guard let self else { return }
                defer {
                    self.isImporting = false
                    self.importTask = nil
                    self.reloadSections()
                }
                await self.importURLs(urls, to: targetSectionID)
            }
        }
    }

    func cancelImport() {
        importTask?.cancel()
    }

    // MARK: - Playback

    func cyclePlaybackMode() {
        playbackMode = playbackMode.next
        playbackModeRevision &+= 1
        UserDefaults.standard.set(playbackMode.rawValue, forKey: "playbackMode")
        updatePlaybackQueue(restart: true)
        schedulePlaybackPresentationUpdate()
    }

    private func updatePlaybackQueue(startingAt track: TrackItem? = nil, restart: Bool = false) {
        playbackQueue = makePlaybackQueue(startingAt: track, restart: restart)
    }

    private func makePlaybackQueue(startingAt track: TrackItem? = nil, restart: Bool = false) -> PlaybackQueue {
        let current = track ?? selectedTrack
        let queueTracks: [TrackItem]
        if playbackMode != .off, let section = current?.section {
            queueTracks = tracks(in: section)
        } else {
            queueTracks = allTracks
        }
        var queue = playbackQueue
        queue.update(
            trackIDs: queueTracks.map(\.id),
            currentID: current?.id,
            shuffle: playbackMode == .shuffle,
            restart: restart
        )
        return queue
    }

    private func handleTrackFinished() {
        guard pendingPlaybackRequestID == nil, let selectedTrackID else { return }
        let finishedRequestID = playbackRequestID
        Task { [weak self] in
            guard let self, self.playbackRequestID == finishedRequestID,
                  self.selectedTrackID == selectedTrackID,
                  self.pendingPlaybackRequestID == nil else { return }
            await self.playRequest(.finished)
        }
    }

    func togglePlayback() {
        if playbackService.isPlaying || playbackService.isStarting {
            pausePlayback()
        } else {
            beginResumePlayback()
        }
    }

    private func resumePlayback() async {
        await beginResumePlayback()?.value
    }

    @discardableResult
    private func beginResumePlayback() -> Task<Void, Never>? {
        guard !playbackService.isPlaying, !playbackService.isStarting else { return nil }
        playbackRequestID = UUID()
        pendingPlaybackRequestID = nil
        if playbackService.duration > 0 {
            // Mark the start synchronously so a second tap can cancel it.
            let start = playbackService.play()
            return Task {
                do {
                    try await start?.value
                } catch is CancellationError {
                    return
                } catch {
                    importError = playbackService.playbackError
                        ?? "Не удалось продолжить воспроизведение. Повторите попытку."
                }
                synchronizePlaybackPresentation(force: true)
            }
        }
        guard let track = selectedTrack else { return nil }
        return Task { await play(track: track) }
    }

    private func pausePlayback() {
        // Cancel a pending cloud-track switch as well as a pending audio start.
        playbackRequestID = UUID()
        pendingPlaybackRequestID = nil
        playbackService.pauseByUser()
        synchronizePlaybackPresentation(force: true)
    }

    func performPlaybackCommand(_ command: NowPlayingService.Command) async {
        switch command {
        case .play:
            await resumePlayback()
        case .pause:
            pausePlayback()
        case .toggle:
            if playbackService.isPlaying || playbackService.isStarting {
                pausePlayback()
            } else {
                await resumePlayback()
            }
        case .previous:
            await playAdjacent(direction: .previous)
        case .next:
            await playAdjacent(direction: .next)
        case let .seek(time):
            seek(to: time)
        }
    }

    func play(track: TrackItem) async {
        await playRequest(.selection(track.id))
    }

    var canPlayPrevious: Bool {
        guard let current = selectedTrack else { return false }
        return !playbackQueue.candidates(
            after: current.id, direction: .previous, wrap: playbackMode == .repeatPlaylist
        ).isEmpty
    }

    var canPlayNext: Bool {
        guard let current = selectedTrack else { return false }
        return !playbackQueue.candidates(
            after: current.id, direction: .next, wrap: playbackMode == .repeatPlaylist
        ).isEmpty
    }

    func playNext() {
        Task { await playAdjacent(direction: .next) }
    }

    func playPrevious() {
        Task { await playAdjacent(direction: .previous) }
    }

    private func playAdjacent(direction: PlaybackQueue.Direction) async {
        await playRequest(.adjacent(direction))
    }

    private func playRequest(_ request: PlaybackRequest) async {
        let candidates: [UUID]
        switch request {
        case let .selection(id):
            guard let track = allTracks.first(where: { $0.id == id }) else { return }
            // Prepare the new order without replacing the current track's queue.
            // A cloud download can suspend and then be cancelled by Pause.
            let queue = makePlaybackQueue(startingAt: track, restart: true)
            candidates = queue.candidates(startingAt: id, direction: .next, wrap: playbackMode == .repeatPlaylist)
        case let .adjacent(direction):
            guard let current = selectedTrack else { return }
            updatePlaybackQueue()
            candidates = playbackQueue.candidates(
                after: current.id, direction: direction, wrap: playbackMode == .repeatPlaylist
            )
        case .finished:
            guard let selectedTrackID else { return }
            updatePlaybackQueue()
            candidates = playbackMode == .repeatOne ? [selectedTrackID] : playbackQueue.candidates(
                after: selectedTrackID, direction: .next, wrap: playbackMode == .repeatPlaylist
            )
            if candidates.isEmpty { activityService.endActivity() }
        }
        guard !candidates.isEmpty else { return }
        await playCandidates(candidates, request: request)
    }

    private func playCandidates(_ candidateIDs: [UUID], request: PlaybackRequest) async {
        let requestID = UUID()
        let modeRevision = playbackModeRevision
        playbackRequestID = requestID
        pendingPlaybackRequestID = requestID
        defer {
            if pendingPlaybackRequestID == requestID { pendingPlaybackRequestID = nil }
        }
        var failureMessage = "Нет доступных аудиофайлов для воспроизведения."

        for candidateID in candidateIDs {
            guard playbackRequestID == requestID, !Task.isCancelled else { return }
            if modeRevision != playbackModeRevision {
                await playRequest(request)
                return
            }
            guard let track = allTracks.first(where: { $0.id == candidateID }) else { continue }
            let title = track.title
            var scopedURL: URL?
            var beganLoading = false
            do {
                let resource = try resolvedResource(for: track)
                scopedURL = resource.scopedURL
                let downloaded = await downloadFromiCloud(
                    resource.url, requestID: requestID, modeRevision: modeRevision
                )
                guard playbackRequestID == requestID, !Task.isCancelled else {
                    scopedURL?.stopAccessingSecurityScopedResource()
                    return
                }
                if modeRevision != playbackModeRevision {
                    scopedURL?.stopAccessingSecurityScopedResource()
                    // Re-evaluate the original action against the still-playing track.
                    // Enabling playlist repeat during a download must not leave it.
                    await playRequest(request)
                    return
                }
                guard downloaded else {
                    scopedURL?.stopAccessingSecurityScopedResource()
                    failureMessage = "Файл «\(title)» недоступен. Повторите импорт или дождитесь загрузки."
                    continue
                }
                guard let currentTrack = allTracks.first(where: { $0.id == candidateID }) else {
                    scopedURL?.stopAccessingSecurityScopedResource()
                    continue
                }
                // Stop the engine before revoking the old file's access grant.
                playbackService.stop()
                stopActiveScopedURLIfNeeded()
                beganLoading = true
                // Own the access grant before activation suspends. A newer
                // request can then stop this file and release its grant safely.
                activeScopedURL = scopedURL
                scopedURL = nil
                selectedTrackID = currentTrack.id
                let isExplicitSelection: Bool
                if case .selection = request { isExplicitSelection = true } else { isExplicitSelection = false }
                updatePlaybackQueue(
                    startingAt: currentTrack,
                    restart: isExplicitSelection || !playbackQueue.orderedIDs.contains(currentTrack.id)
                )
                nowPlayingTitle = currentTrack.displayName
                nowPlayingArtwork = currentTrack.artwork
                try await playbackService.loadAndPlay(url: resource.url)
                try Task.checkCancellation()
                guard playbackRequestID == requestID else { return }
                importError = nil
                if currentTrack.isCorrupted {
                    try? storageService.setCorrupted(false, for: currentTrack)
                }
                if let sectionID = currentTrack.section?.id {
                    lastPlayedSectionID = sectionID
                    UserDefaults.standard.set(sectionID.uuidString, forKey: "lastPlayedSectionID")
                }
                synchronizePlaybackPresentation(force: true)
                return
            } catch {
                scopedURL?.stopAccessingSecurityScopedResource()
                guard playbackRequestID == requestID else { return }
                // Seek/pause may supersede only the audio start while keeping
                // the selected file. Do not stop that newer playback request.
                if error is CancellationError, !Task.isCancelled { return }
                if beganLoading {
                    playbackService.stop()
                    stopActiveScopedURLIfNeeded()
                }
                guard !Task.isCancelled else { return }
                if let playbackError = error as? AudioPlaybackService.PlaybackError {
                    switch playbackError {
                    case .audioUnavailable:
                        resetPlayback()
                        importError = "Не удалось запустить аудиовыход. Попробуйте воспроизведение ещё раз."
                        return
                    case .invalidAudioFile:
                        markCorrupted(track)
                    }
                }
                failureMessage = "Не удалось воспроизвести «\(title)». Проверьте файл или повторите импорт."
            }
        }
        guard playbackRequestID == requestID, !Task.isCancelled else { return }
        resetPlayback()
        importError = failureMessage
    }

    func seek(to time: TimeInterval) {
        playbackService.seek(to: time)
        synchronizePlaybackPresentation(force: true)
    }

    // MARK: - Remove

    func removeTrack(_ track: TrackItem) {
        let removesSelectedTrack = track.id == selectedTrackID
        do {
            try storageService.removeTrack(track)
            if removesSelectedTrack {
                resetPlayback()
            }
            reloadSections()
        } catch {
            importError = "Не удалось удалить трек. Повторите попытку."
        }
    }

    @discardableResult
    func removeTracks(withIDs trackIDs: Set<UUID>, from section: PlaylistSection) -> Bool {
        guard !isImporting else {
            importError = "Дождитесь завершения импорта перед редактированием плейлиста."
            return false
        }
        guard let currentSection = sections.first(where: { $0.id == section.id }) else {
            importError = "Плейлист больше не существует."
            return false
        }
        let scopedIDs = Set(tracks(in: currentSection).map(\.id)).intersection(trackIDs)
        guard !scopedIDs.isEmpty else { return true }
        let removesSelectedTrack = selectedTrackID.map { scopedIDs.contains($0) } ?? false
        do {
            try storageService.removeTracks(withIDs: scopedIDs, from: currentSection)
            if removesSelectedTrack {
                resetPlayback()
            }
            reloadSections()
            return true
        } catch {
            importError = "Не удалось удалить выбранные треки. Повторите попытку."
            return false
        }
    }

    @discardableResult
    func moveTracks(in section: PlaylistSection, from source: IndexSet, to destination: Int) -> Bool {
        guard !isImporting else {
            importError = "Дождитесь завершения импорта перед редактированием плейлиста."
            return false
        }
        guard let currentSection = sections.first(where: { $0.id == section.id }) else {
            importError = "Плейлист больше не существует."
            return false
        }
        var reorderedTracks = tracks(in: currentSection)
        guard source.allSatisfy({ reorderedTracks.indices.contains($0) }),
              (0...reorderedTracks.count).contains(destination) else {
            importError = "Список треков изменился. Повторите перемещение."
            return false
        }
        guard !source.isEmpty else { return true }
        let previousOrder = reorderedTracks.map(\.id)
        reorderedTracks.move(fromOffsets: source, toOffset: destination)
        let nextOrder = reorderedTracks.map(\.id)
        guard nextOrder != previousOrder else { return true }
        do {
            try storageService.setTrackOrder(nextOrder, in: currentSection)
            reloadSections()
            return true
        } catch {
            importError = "Не удалось сохранить порядок треков. Повторите попытку."
            return false
        }
    }

    // MARK: - Export

    func exportPlaylistsJSON() -> Data {
        var result: [String: [[String: String]]] = [:]
        let reservedNames = Set(sections.map(\.name))
        for section in sections {
            let tracks = storageService.sortedTracks(in: section).map { track in
                [
                    "author": track.artist,
                    "title": track.title,
                    "path": track.filePath
                ]
            }
            var key = section.name
            var suffix = 2
            while result[key] != nil {
                repeat {
                    key = "\(section.name) (\(suffix))"
                    suffix += 1
                } while reservedNames.contains(key)
            }
            result[key] = tracks
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

    private func setupPlaybackPresentation() {
        _ = nowPlayingService
        playbackPresentationCancellable = Publishers.CombineLatest4(
            playbackService.$currentTime, playbackService.$duration,
            playbackService.$isPlaying, playbackService.$isStarting
        )
            .sink { [weak self] _ in
                self?.schedulePlaybackPresentationUpdate()
            }
    }

    private func schedulePlaybackPresentationUpdate() {
        guard !presentationUpdateScheduled else { return }
        presentationUpdateScheduled = true
        // @Published emits before storage changes. Coalesce the synchronous
        // stop/load/start changes, then read one committed playback snapshot.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.presentationUpdateScheduled = false
            self.synchronizePlaybackPresentation()
        }
    }

    func refreshPlaybackPresentation() {
        activityService.retryWhenForegrounded()
        synchronizePlaybackPresentation(force: true)
    }

    private func synchronizePlaybackPresentation(force: Bool = false) {
        let duration = playbackService.duration
        guard let selectedTrackID, let track = selectedTrack,
              duration.isFinite, duration > 0 else {
            // Keep the current activity through a track handoff; the next
            // successfully loaded track replaces its content in place.
            if pendingPlaybackRequestID == nil {
                nowPlayingService.clear()
                activityService.endActivity()
            }
            return
        }
        let time = playbackService.currentTime.isFinite
            ? min(duration, max(0, playbackService.currentTime)) : 0
        let snapshot = NowPlayingService.Snapshot(
            trackID: selectedTrackID,
            title: track.displayName,
            artist: track.displayArtist ?? "",
            duration: duration,
            currentTime: time,
            isPlaying: playbackService.isPlaying,
            canPlayPrevious: canPlayPrevious,
            canPlayNext: canPlayNext
        )
        nowPlayingService.update(snapshot, force: force)
        activityService.synchronize(
            ATPlayerActivityAttributes.ContentState(
                trackID: snapshot.trackID,
                trackTitle: snapshot.title,
                artistName: snapshot.artist,
                duration: snapshot.duration,
                currentTime: snapshot.currentTime,
                isPlaying: snapshot.isPlaying,
                playbackStartDate: Date.now.addingTimeInterval(-time),
                canPlayPrevious: snapshot.canPlayPrevious,
                canPlayNext: snapshot.canPlayNext
            ),
            allowStart: UIApplication.shared.applicationState == .active,
            force: force
        )
    }

    private func resetPlayback() {
        playbackRequestID = UUID()
        pendingPlaybackRequestID = nil
        playbackService.stop()
        stopActiveScopedURLIfNeeded()
        selectedTrackID = nil
        updatePlaybackQueue(restart: true)
        nowPlayingTitle = "Готов к воспроизведению"
        nowPlayingArtwork = nil
        nowPlayingService.clear()
        activityService.endActivity()
    }

    private func markCorrupted(_ track: TrackItem) {
        do {
            try storageService.setCorrupted(true, for: track)
            reloadSections()
        } catch {
            importError = "Не удалось сохранить состояние трека."
        }
    }

    private func importURLs(_ urls: [URL], to sectionID: UUID) async {
        let fileManager = FileManager.default
        for url in urls {
            guard !Task.isCancelled else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
            guard didAccess || fileManager.isReadableFile(atPath: url.path) else {
                importError = "Нет доступа к «\(url.lastPathComponent)». Выберите файл повторно."
                continue
            }
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            let directoryURL = exists && isDirectory.boolValue ? url : nil
            let files: [URL]
            if let directoryURL {
                files = await collectAudioFiles(in: directoryURL)
            } else {
                files = [url]
            }
            for fileURL in files {
                guard !Task.isCancelled else { return }
                guard await downloadFromiCloud(fileURL) else { continue }
                guard let section = sections.first(where: { $0.id == sectionID }) else {
                    importError = "Плейлист для импорта был удалён."
                    return
                }
                await importSingleTrack(at: fileURL, directoryURL: directoryURL, to: section)
                await Task.yield()
            }
        }
    }

    private func importSingleTrack(at url: URL, directoryURL: URL?, to section: PlaylistSection) async {
        let sectionID = section.id
        do {
            let bookmark = TrackBookmark(
                file: try url.bookmarkData(options: .minimalBookmark),
                directory: try directoryURL?.bookmarkData(options: .minimalBookmark)
            )
            let asset = AVURLAsset(url: url)
            let metadata = try await extractMetadata(
                from: asset,
                fallbackName: url.deletingPathExtension().lastPathComponent
            )
            try Task.checkCancellation()
            guard let currentSection = sections.first(where: { $0.id == sectionID }) else { return }
            _ = try storageService.appendTrack(
                title: metadata.title,
                artist: metadata.artist,
                url: url,
                bookmark: try JSONEncoder().encode(bookmark),
                duration: metadata.duration,
                artwork: metadata.artwork,
                to: currentSection
            )
        } catch is CancellationError {
            return
        } catch {
            importError = "Не удалось импортировать «\(url.lastPathComponent)». Проверьте формат и доступ к файлу."
        }
    }

    private func isDownloaded(_ url: URL) -> Bool {
        do {
            var resourceURL = url
            resourceURL.removeCachedResourceValue(forKey: .ubiquitousItemDownloadingStatusKey)
            let values = try resourceURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            let status = values.ubiquitousItemDownloadingStatus
            return status == .current || status == .downloaded
                || (status == nil && FileManager.default.isReadableFile(atPath: url.path))
        } catch {
            return FileManager.default.isReadableFile(atPath: url.path)
        }
    }

    private func downloadFromiCloud(
        _ url: URL,
        requestID: UUID? = nil,
        modeRevision: UInt? = nil
    ) async -> Bool {
        func canContinue() -> Bool {
            !Task.isCancelled && (requestID == nil || requestID == playbackRequestID)
                && (modeRevision == nil || modeRevision == playbackModeRevision)
        }
        guard canContinue() else { return false }
        guard !isDownloaded(url) else { return true }
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            guard canContinue() else { return false }
            importError = "Не удалось загрузить «\(url.lastPathComponent)». Проверьте доступ к iCloud."
            return false
        }
        for _ in 0..<Self.cloudDownloadAttempts {
            guard canContinue() else { return false }
            do {
                try await Task.sleep(for: Self.cloudDownloadPollInterval)
            } catch {
                return false
            }
            guard canContinue() else { return false }
            if isDownloaded(url) { return true }
        }
        guard canContinue() else { return false }
        importError = "Время ожидания загрузки «\(url.lastPathComponent)» из iCloud истекло."
        return false
    }

    private func extractMetadata(
        from asset: AVURLAsset,
        fallbackName: String
    ) async throws -> (title: String, artist: String, duration: Double, artwork: Data?) {
        let rawDuration = try await asset.load(.duration).seconds
        let duration = rawDuration.isFinite && rawDuration > 0 ? rawDuration : 0
        let metadataItems = (try? await asset.load(.commonMetadata)) ?? []

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

        let titleValue = try? await titleItem?.load(.stringValue)
        let artistValue = try? await artistItem?.load(.stringValue)
        let artwork = try? await artworkItem?.load(.dataValue)
        let title = titleValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = artistValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (title.isEmpty ? fallbackName : title, artist, duration, artwork)
    }

    private let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "alac", "caf"]

    private func collectAudioFiles(in directoryURL: URL) async -> [URL] {
        var result: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .ubiquitousItemDownloadingStatusKey],
            options: [.skipsHiddenFiles]
        ) else { return result }

        while let fileURL = enumerator.nextObject() as? URL {
            // Let cancellation and UI events run while scanning a large library.
            await Task.yield()
            guard !Task.isCancelled else { break }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true,
               audioExtensions.contains(fileURL.pathExtension.lowercased()) {
                result.append(fileURL)
            }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func resolvedResource(for track: TrackItem) throws -> (url: URL, scopedURL: URL?) {
        var bookmark = (try? JSONDecoder().decode(TrackBookmark.self, from: track.bookmark))
            ?? TrackBookmark(file: track.bookmark, directory: nil)
        var scopedURL: URL?
        do {
            var directoryStale = false
            if let directoryData = bookmark.directory {
                let directoryURL = try URL(
                    resolvingBookmarkData: directoryData,
                    bookmarkDataIsStale: &directoryStale
                )
                if directoryURL.startAccessingSecurityScopedResource() {
                    scopedURL = directoryURL
                } else if !FileManager.default.isReadableFile(atPath: directoryURL.path) {
                    throw CocoaError(.fileReadNoPermission)
                }
                if directoryStale {
                    bookmark.directory = try directoryURL.bookmarkData(options: .minimalBookmark)
                }
            }
            var fileStale = false
            let url = try URL(resolvingBookmarkData: bookmark.file, bookmarkDataIsStale: &fileStale)
            if scopedURL == nil, url.startAccessingSecurityScopedResource() {
                scopedURL = url
            }
            if fileStale {
                bookmark.file = try url.bookmarkData(options: .minimalBookmark)
            }
            if fileStale || directoryStale || track.filePath != url.path {
                try storageService.updateBookmark(
                    for: track,
                    bookmark: try JSONEncoder().encode(bookmark),
                    url: url
                )
            }
            return (url, scopedURL)
        } catch {
            scopedURL?.stopAccessingSecurityScopedResource()
            throw error
        }
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
