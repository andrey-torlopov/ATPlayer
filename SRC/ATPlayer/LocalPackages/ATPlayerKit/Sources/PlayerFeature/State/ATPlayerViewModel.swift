import AppLocalization
import FolderDomain
import LibraryDomain
import PlaybackDomain
import Combine
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
public final class ATPlayerViewModel: ObservableObject {

    @Published var sections: [Playlist] = []
    @Published var selectedTrackID: UUID?
    @Published var showImporter = false
    @Published var showSettings = false
    @Published private var currentTrackTitle: String?
    var nowPlayingTitle: String { currentTrackTitle ?? L10n.text("Готов к воспроизведению") }
    @Published var nowPlayingArtwork: Data?
    @Published var importError: String?
    @Published var importTargetSection: Playlist?
    @Published var lastPlayedSectionID: UUID?
    @Published private(set) var preparingTrackTitle: String?
    @Published private(set) var isImporting = false
    @Published private(set) var playbackMode: PlaybackMode = .off
    @Published var radioSettings = RadioSettings()
    let radioPreferences: RadioPreferences

    let supportedTypes: [UTType] = SupportedAudioFormats.fileExtensions.sorted()
        .compactMap { UTType(filenameExtension: $0) } + [.folder]
    let playbackService: any AudioPlaying
    var playbackState: AudioPlaybackState { playbackService.state }
    let activityService: any ActivityPresenting
    private let storageService: any PlaylistStoring
    private let defaults: UserDefaults
    private let folderAccess: (any FolderAccessing)?
    private let mediaAccess: any MediaResourceAccess
    private let nowPlayingService: any NowPlayingPresenting
    private var activeScopedURL: URL?
    private var playbackPresentationCancellable: AnyCancellable?
    private var playbackStatusCancellable: AnyCancellable?
    private var presentationUpdateScheduled = false
    private var playbackErrorCancellable: AnyCancellable?
    private var playbackRequestID = UUID()
    private var pendingPlaybackRequestID: UUID?
    private var importTask: Task<Void, Never>?
    private var playbackQueue = PlaybackQueue()
    private var playbackModeRevision: UInt = 0
    private var playbackSource: PlaybackSource = .playlists
    private var pendingFolderSourceID: UUID?
    private var activeLease: CachedAudioLease?
    private var preparationTask: Task<CachedAudioLease, Error>?
    private var radioPreparationTask: Task<Void, Never>?
    private var radioRequestID: UUID?
    private var radioTargetID: UUID?
    private var radioRequest: PlaybackRequest?
    private var radioRequestSource: PlaybackSource?
    private var radioRequestQueue: PlaybackQueue?
    private var radioIsPrefetch = false
    private var radioPending: PendingRadioTrack?
    private var activeRadioHandle: AudioPreparedTrack?
    private var radioTimeCancellable: AnyCancellable?
    private var isCancellingRadioPreparation = false
    private var radioControlRevision: UInt = 0
    private var radioHistory: [UUID] = []
    private var radioHistoryPosition = 0

    private struct PendingRadioTrack {
        let handle: AudioPreparedTrack
        let track: PlaylistTrack
        let source: PlaybackSource
        let request: PlaybackRequest
        let scopedURL: URL?
        let lease: CachedAudioLease?
    }

    private struct FolderQueue {
        let source: FolderSource
        let entries: [FolderEntry]
        let tracks: [PlaylistTrack]
    }

    private enum PlaybackSource {
        case playlists
        case folder(FolderQueue)

        var folderID: UUID? {
            if case let .folder(queue) = self { return queue.source.id }
            return nil
        }
    }

    private enum PlaybackRequest {
        case selection(UUID, PlaybackSource)
        case adjacent(PlaybackQueue.Direction)
        case finished
    }

    public init(
        storage: any PlaylistStoring,
        audio: any AudioPlaying,
        activity: any ActivityPresenting,
        nowPlaying: any NowPlayingPresenting,
        mediaAccess: any MediaResourceAccess,
        defaults: UserDefaults = .standard,
        folderAccess: (any FolderAccessing)? = nil
    ) {
        self.folderAccess = folderAccess
        self.defaults = defaults
        self.radioPreferences = RadioPreferences(defaults: defaults)
        self.storageService = storage
        self.playbackService = audio
        self.activityService = activity
        self.nowPlayingService = nowPlaying
        self.mediaAccess = mediaAccess
        radioSettings = radioPreferences.load()
        audio.applyRadioSettings(radioSettings)
        nowPlaying.handleCommand = { [weak self] command in
            Task { @MainActor [weak self] in
                await self?.performPlaybackCommand(command)
            }
        }
        if let savedMode = defaults.string(forKey: "playbackMode")
            .flatMap(PlaybackMode.init(rawValue:)) {
            playbackMode = savedMode
        } else {
            // Preserve preferences from the earlier two-button development build.
            let legacyRepeat = defaults.string(forKey: "playbackRepeatMode")
            if legacyRepeat == "one" {
                playbackMode = .repeatOne
            } else if defaults.bool(forKey: "playbackShuffleEnabled") {
                playbackMode = .shuffle
            } else if legacyRepeat == "playlist" {
                playbackMode = .repeatPlaylist
            }
            defaults.set(playbackMode.rawValue, forKey: "playbackMode")
        }
        if let savedID = defaults.string(forKey: "lastPlayedSectionID") {
            lastPlayedSectionID = UUID(uuidString: savedID)
        }
        activityService.endAllStaleActivities()
        playbackService.onTrackFinished = { [weak self] in
            self?.handleTrackFinished()
        }
        playbackService.onTrackStarted = { [weak self] handle in
            self?.commitRadioTrack(handle)
        }
        playbackService.onTrackReleased = { [weak self] handle in
            self?.releaseRadioTrack(handle)
        }
        playbackService.onTransportCancelled = { [weak self] in
            self?.cancelRadioPreparation()
        }
        setupPlaybackPresentation()
        playbackErrorCancellable = playbackState.$playbackError
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.importError = message
            }
        reloadSections()
    }

    deinit {
        preparationTask?.cancel()
        radioPreparationTask?.cancel()
        // Avoid isolated-deinit backdeployment on iOS 26.0–26.3. Capture resources,
        // never self, while still releasing audio and its grants on the UI actor.
        let cleanup: @MainActor @Sendable () -> Void = { [playbackService, activeLease, folderAccess, activeScopedURL, radioPending] in
            playbackService.onTrackStarted = nil
            playbackService.onTrackReleased = nil
            playbackService.onTransportCancelled = nil
            playbackService.stop()
            if let lease = activeLease, let access = folderAccess {
                Task { await access.release(lease) }
            }
            activeScopedURL?.stopAccessingSecurityScopedResource()
            if let lease = radioPending?.lease, let access = folderAccess {
                Task { await access.release(lease) }
            }
            radioPending?.scopedURL?.stopAccessingSecurityScopedResource()
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated { cleanup() }
        } else {
            Task { @MainActor in cleanup() }
        }
    }

    public func shutdown() {
        cancelImport()
        resetPlayback()
        nowPlayingService.handleCommand = nil
        playbackService.onTrackFinished = nil
        playbackService.onTrackStarted = nil
        playbackService.onTrackReleased = nil
        playbackService.onTransportCancelled = nil
    }

    func reloadSections() {
        do {
            _ = try storageService.ensureDefaultSection()
            sections = try storageService.fetchSections()
            updatePlaybackQueue()
            refreshRadioQueue()
            schedulePlaybackPresentationUpdate()
        } catch {
            importError = L10n.text("Не удалось загрузить плейлисты. Повторите попытку.")
        }
    }

    var allTracks: [PlaylistTrack] {
        sections.flatMap { storageService.sortedTracks(in: $0) }
    }

    func tracks(in section: Playlist) -> [PlaylistTrack] {
        storageService.sortedTracks(in: section)
    }

    // MARK: - Sections

    func addSection(name: String) {
        do {
            _ = try storageService.createSection(name: name)
            reloadSections()
        } catch {
            importError = L10n.text("Не удалось создать плейлист. Повторите попытку.")
        }
    }

    func removeSection(_ section: Playlist) {
        let sectionID = section.id
        let removesSelectedTrack = section.tracks.contains { $0.id == selectedTrackID }
        do {
            try storageService.removeSection(section)
            if removesSelectedTrack {
                resetPlayback()
            }
            if lastPlayedSectionID == sectionID {
                lastPlayedSectionID = nil
                defaults.removeObject(forKey: "lastPlayedSectionID")
            }
            reloadSections()
        } catch {
            importError = L10n.text("Не удалось удалить плейлист. Повторите попытку.")
        }
    }

    func renameSection(_ section: Playlist, to name: String) {
        do {
            try storageService.renameSection(section, to: name)
            reloadSections()
        } catch {
            importError = L10n.text("Не удалось переименовать плейлист. Повторите попытку.")
        }
    }

    @discardableResult
    func moveSections(from source: IndexSet, to destination: Int) -> Bool {
        guard !isImporting else {
            importError = L10n.text("Дождитесь завершения импорта перед изменением порядка плейлистов.")
            return false
        }
        var reorderedSections = sections
        guard source.allSatisfy({ reorderedSections.indices.contains($0) }),
              (0...reorderedSections.count).contains(destination) else {
            importError = L10n.text("Список плейлистов изменился. Повторите перемещение.")
            return false
        }
        guard !source.isEmpty else { return true }
        let previousOrder = reorderedSections.map(\.id)
        reorderedSections.move(fromOffsets: source, toOffset: destination)
        let nextOrder = reorderedSections.map(\.id)
        guard nextOrder != previousOrder else { return true }
        do {
            try storageService.setSectionOrder(nextOrder)
            // Rebuild normal traversal in the saved order. The current file and
            // shuffle history retain their identities and audio is not restarted.
            reloadSections()
            return true
        } catch {
            importError = L10n.text("Не удалось сохранить порядок плейлистов. Повторите попытку.")
            return false
        }
    }

    // MARK: - Import

    func requestImport(to section: Playlist) {
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
            importError = L10n.text("Не удалось открыть выбранные файлы. Повторите импорт.")
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

    var playbackModeTitle: String { modeTitle(playbackMode) }
    var nextPlaybackModeTitle: String { modeTitle(playbackMode.next) }

    private func modeTitle(_ mode: PlaybackMode) -> String {
        mode == .repeatPlaylist && playbackSource.folderID != nil ? L10n.text("Повтор папки") : mode.title
    }

    func cyclePlaybackMode() {
        playbackMode = playbackMode.next
        playbackModeRevision &+= 1
        defaults.set(playbackMode.rawValue, forKey: "playbackMode")
        updatePlaybackQueue(restart: true)
        radioHistory = selectedTrackID.map { [$0] } ?? []
        radioHistoryPosition = 0
        refreshRadioQueue(force: true)
        schedulePlaybackPresentationUpdate()
    }

    private func sourceTracks(_ source: PlaybackSource) -> [PlaylistTrack] {
        switch source {
        case .playlists: allTracks
        case let .folder(queue): queue.tracks
        }
    }

    private func updatePlaybackQueue(startingAt track: PlaylistTrack? = nil, restart: Bool = false) {
        playbackQueue = makePlaybackQueue(startingAt: track, source: playbackSource, restart: restart)
    }

    private func makePlaybackQueue(
        startingAt track: PlaylistTrack? = nil,
        source: PlaybackSource,
        restart: Bool = false
    ) -> PlaybackQueue {
        let current = track ?? selectedTrack
        let queueTracks: [PlaylistTrack]
        if case let .folder(folder) = source {
            queueTracks = folder.tracks
        } else if playbackMode != .off, let section = current?.section {
            queueTracks = tracks(in: section)
        } else {
            queueTracks = allTracks
        }
        var queue = playbackQueue
        queue.update(
            trackIDs: queueTracks.map(\.id), currentID: current?.id,
            shuffle: playbackMode == .shuffle, restart: restart
        )
        return queue
    }

    /// Captures a directory queue; browsing elsewhere never mutates this snapshot.
    public func playFolder(source: FolderSource, entries: [FolderEntry], selectedID: UUID) async {
        guard folderAccess != nil else { return }
        let audio = entries.filter { $0.kind == .audio }
        guard audio.contains(where: { $0.id == selectedID }) else { return }
        let tracks = audio.enumerated().map { index, entry in
            PlaylistTrack(
                id: entry.id, title: URL(fileURLWithPath: entry.name).deletingPathExtension().lastPathComponent,
                artist: "", filePath: entry.relativePath, bookmark: Data(), duration: 0, order: index
            )
        }
        let queue = FolderQueue(source: source, entries: audio, tracks: tracks)
        await playRequest(.selection(selectedID, .folder(queue)))
    }

    public func removeFolderSource(id: UUID) {
        if playbackSource.folderID == id {
            resetPlayback()
        } else if pendingFolderSourceID == id {
            invalidatePreparation()
        }
    }

    private func invalidatePreparation() {
        cancelRadioPreparation()
        playbackRequestID = UUID()
        pendingPlaybackRequestID = nil
        pendingFolderSourceID = nil
        preparingTrackTitle = nil
        preparationTask?.cancel()
        preparationTask = nil
    }

    private func handleTrackFinished() {
        if radioRequestID != nil {
            // The already prepared transaction owns EOF. A delayed candidate
            // keeps the committed selection and exposes preparation after EOF.
            if let id = radioTargetID, let source = radioRequestSource {
                preparingTrackTitle = sourceTracks(source).first { $0.id == id }?.displayName
            }
            return
        }
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
        playbackService.reconcilePlaybackState()
        if pendingPlaybackRequestID != nil || playbackState.isPlaying || playbackState.isStarting {
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
        playbackService.reconcilePlaybackState()
        guard pendingPlaybackRequestID == nil, !playbackState.isPlaying, !playbackState.isStarting else { return nil }
        playbackRequestID = UUID()
        pendingPlaybackRequestID = nil
        if playbackState.duration > 0 {
            if playbackService.supportsPreparedTransitions,
               playbackState.currentTime >= playbackState.duration {
                return Task { await playRequest(.finished) }
            }
            // Mark the start synchronously so a second tap can cancel it.
            let start = playbackService.play()
            return Task {
                do {
                    try await start?.value
                } catch is CancellationError {
                    return
                } catch {
                    importError = playbackState.playbackError
                        ?? L10n.text("Не удалось продолжить воспроизведение. Повторите попытку.")
                }
                synchronizePlaybackPresentation(force: true)
                beginRadioPrefetch()
            }
        }
        guard let track = selectedTrack else { return nil }
        return Task { await play(track: track) }
    }

    private func pausePlayback() {
        // Cancel a pending cloud-track switch as well as a pending audio start.
        invalidatePreparation()
        playbackService.pauseByUser()
        synchronizePlaybackPresentation(force: true)
    }

    public func performPlaybackCommand(_ command: PlaybackCommand) async {
        playbackService.reconcilePlaybackState()
        switch command {
        case .play:
            await resumePlayback()
        case .pause:
            pausePlayback()
        case .toggle:
            if pendingPlaybackRequestID != nil || playbackState.isPlaying || playbackState.isStarting {
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

    func play(track: PlaylistTrack) async {
        await playRequest(.selection(track.id, .playlists))
    }

    var canPlayPrevious: Bool {
        !navigationCandidates(direction: .previous).isEmpty
    }

    var canPlayNext: Bool {
        !navigationCandidates(direction: .next).isEmpty
    }

    private func navigationCandidates(direction: PlaybackQueue.Direction) -> [UUID] {
        guard let current = selectedTrack else { return [] }
        let hasManualTarget = radioRequestID != nil && !radioIsPrefetch
        if !hasManualTarget, playbackMode == .shuffle,
           playbackService.supportsPreparedTransitions,
           radioHistory.contains(current.id) {
            if case .previous = direction {
                return Array(radioHistory.prefix(radioHistoryPosition).reversed())
            }
            if radioHistoryPosition + 1 < radioHistory.count {
                return Array(radioHistory.suffix(from: radioHistoryPosition + 1))
            }
        }
        let source = hasManualTarget ? (radioRequestSource ?? playbackSource) : playbackSource
        let anchor = hasManualTarget ? (radioTargetID ?? current.id) : current.id
        let track = sourceTracks(source).first { $0.id == anchor } ?? current
        let queue = hasManualTarget
            ? (radioRequestQueue ?? makePlaybackQueue(startingAt: track, source: source))
            : makePlaybackQueue(startingAt: track, source: source)
        return queue.candidates(after: anchor, direction: direction, wrap: playbackMode == .repeatPlaylist)
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
        let source: PlaybackSource
        let requestQueue: PlaybackQueue
        switch request {
        case let .selection(id, selectedSource):
            source = selectedSource
            guard let track = sourceTracks(source).first(where: { $0.id == id }) else { return }
            // Prepare the new order without replacing the current track's queue.
            // A cloud download can suspend and then be cancelled by Pause.
            let queue = makePlaybackQueue(startingAt: track, source: source, restart: true)
            requestQueue = queue
            candidates = queue.candidates(startingAt: id, direction: .next, wrap: playbackMode == .repeatPlaylist)
        case let .adjacent(direction):
            source = radioIsPrefetch ? playbackSource : (radioRequestSource ?? playbackSource)
            guard selectedTrack != nil else { return }
            updatePlaybackQueue()
            requestQueue = radioRequestQueue ?? playbackQueue
            candidates = navigationCandidates(direction: direction)
        case .finished:
            source = playbackSource
            guard let selectedTrackID else { return }
            updatePlaybackQueue()
            requestQueue = playbackQueue
            candidates = playbackMode == .repeatOne ? [selectedTrackID] : playbackQueue.candidates(
                after: selectedTrackID, direction: .next, wrap: playbackMode == .repeatPlaylist
            )
            if candidates.isEmpty { activityService.endActivity() }
        }
        guard !candidates.isEmpty else { return }
        if playbackService.supportsPreparedTransitions, playbackState.duration > 0 {
            await startRadioRequest(candidates, source: source, request: request,
                                    queue: requestQueue, prefetch: false)
            return
        }
        cancelRadioPreparation()
        await playCandidates(candidates, source: source, request: request)
    }

    private func playCandidates(_ candidateIDs: [UUID], source: PlaybackSource, request: PlaybackRequest) async {
        let requestID = UUID()
        let modeRevision = playbackModeRevision
        preparationTask?.cancel()
        preparationTask = nil
        playbackRequestID = requestID
        pendingPlaybackRequestID = requestID
        pendingFolderSourceID = source.folderID
        defer {
            if pendingPlaybackRequestID == requestID {
                pendingPlaybackRequestID = nil
                pendingFolderSourceID = nil
                preparingTrackTitle = nil
                preparationTask = nil
            }
        }
        var replacedActiveFile = false
        var failureMessage = L10n.text("Нет доступных аудиофайлов для воспроизведения.")

        for candidateID in candidateIDs {
            guard playbackRequestID == requestID, !Task.isCancelled else { return }
            if modeRevision != playbackModeRevision {
                await playRequest(request)
                return
            }
            guard let track = sourceTracks(source).first(where: { $0.id == candidateID }) else { continue }
            let title = track.title
            var scopedURL: URL?
            var candidateLease: CachedAudioLease?
            var beganLoading = false
            preparingTrackTitle = track.displayName
            do {
                let resourceURL: URL
                if case let .folder(queue) = source {
                    guard let access = folderAccess,
                          let entry = queue.entries.first(where: { $0.id == candidateID }) else { continue }
                    let task = Task { try await access.prepare(source: queue.source, entry: entry, priority: .playback) }
                    preparationTask = task
                    let lease = try await withTaskCancellationHandler {
                        try await task.value
                    } onCancel: { task.cancel() }
                    candidateLease = lease
                    resourceURL = lease.url
                } else {
                    let resource = try resolvedResource(for: track)
                    scopedURL = resource.scopedURL
                    resourceURL = resource.url
                    let downloaded = await downloadFromiCloud(
                        resource.url, requestID: requestID, modeRevision: modeRevision
                    )
                    guard downloaded else {
                        scopedURL?.stopAccessingSecurityScopedResource()
                        scopedURL = nil
                        guard playbackRequestID == requestID, !Task.isCancelled else { return }
                        if modeRevision != playbackModeRevision { await playRequest(request); return }
                        failureMessage = L10n.format("Файл «%@» недоступен. Повторите импорт или дождитесь загрузки.", title)
                        continue
                    }
                }
                guard playbackRequestID == requestID, !Task.isCancelled else {
                    scopedURL?.stopAccessingSecurityScopedResource()
                    if let lease = candidateLease { await folderAccess?.release(lease) }
                    return
                }
                if modeRevision != playbackModeRevision {
                    scopedURL?.stopAccessingSecurityScopedResource()
                    if let lease = candidateLease { await folderAccess?.release(lease) }
                    await playRequest(request)
                    return
                }
                guard let currentTrack = sourceTracks(source).first(where: { $0.id == candidateID }) else {
                    scopedURL?.stopAccessingSecurityScopedResource()
                    if let lease = candidateLease { await folderAccess?.release(lease) }
                    continue
                }
                // Stop the engine before revoking the old file's access grant.
                playbackService.stop()
                stopActiveScopedURLIfNeeded()
                beganLoading = true
                replacedActiveFile = true
                playbackSource = source
                activeLease = candidateLease
                candidateLease = nil
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
                currentTrackTitle = currentTrack.displayName
                nowPlayingArtwork = currentTrack.artwork
                try await playbackService.loadAndPlay(url: resourceURL)
                try Task.checkCancellation()
                guard playbackRequestID == requestID else { return }
                importError = nil
                recordRadioHistory(currentTrack.id, explicit: isExplicitSelection)
                if case .playlists = source, currentTrack.isCorrupted {
                    try? storageService.setCorrupted(false, for: currentTrack)
                }
                if let sectionID = currentTrack.section?.id {
                    lastPlayedSectionID = sectionID
                    defaults.set(sectionID.uuidString, forKey: "lastPlayedSectionID")
                }
                synchronizePlaybackPresentation(force: true)
                beginRadioPrefetch()
                return
            } catch {
                scopedURL?.stopAccessingSecurityScopedResource()
                if let lease = candidateLease { await folderAccess?.release(lease) }
                guard playbackRequestID == requestID else { return }
                // Seek/pause may supersede only the audio start while keeping
                // the selected file. Do not stop that newer playback request.
                if error is CancellationError, !Task.isCancelled { return }
                if beganLoading {
                    playbackService.stop()
                    stopActiveScopedURLIfNeeded()
                }
                guard !Task.isCancelled else { return }
                if let playbackError = error as? PlaybackError {
                    switch playbackError {
                    case .audioUnavailable:
                        resetPlayback()
                        importError = L10n.text("Не удалось запустить аудиовыход. Попробуйте воспроизведение ещё раз.")
                        return
                    case .invalidAudioFile:
                        if case .playlists = source { markCorrupted(track) }
                    }
                }
                failureMessage = source.folderID == nil
                    ? L10n.format("Не удалось воспроизвести «%@». Проверьте файл или повторите импорт.", title)
                    : (error as? FolderAccessError)?.localizedDescription
                        ?? L10n.format("Не удалось подготовить «%@». Проверьте сеть, свободное место и доступ к папке; затем обновите список.", title)
            }
        }
        guard playbackRequestID == requestID, !Task.isCancelled else { return }
        // A failed new folder preparation must not interrupt the previous file.
        if case .selection = request, source.folderID != nil, !replacedActiveFile,
           playbackState.duration > 0 {
            importError = failureMessage
        } else {
            resetPlayback()
            importError = failureMessage
        }
    }

    func seek(to time: TimeInterval) {
        invalidatePreparation()
        playbackService.seek(to: time)
        synchronizePlaybackPresentation(force: true)
        if time < playbackState.duration { beginRadioPrefetch() }
    }

    // MARK: - Prepared track handoffs

    private func beginRadioPrefetch() {
        guard playbackService.supportsPreparedTransitions,
              radioRequestID == nil,
              playbackState.isPlaying, let selectedTrackID else { return }
        updatePlaybackQueue()
        let candidates = playbackMode == .repeatOne ? [selectedTrackID] : playbackQueue.candidates(
            after: selectedTrackID, direction: .next, wrap: playbackMode == .repeatPlaylist
        )
        guard !candidates.isEmpty else { return }
        launchRadioRequest(candidates, source: playbackSource, request: .finished,
                           queue: playbackQueue, prefetch: true)
    }

    private func refreshRadioQueue(force: Bool = false) {
        guard playbackService.supportsPreparedTransitions else { return }
        let request = radioRequest
        let isManual = radioRequestID != nil && !radioIsPrefetch
        let targetExists = radioTargetID.map { id in
            sourceTracks(radioRequestSource ?? playbackSource).contains { $0.id == id }
        } ?? true
        guard force || !targetExists || radioIsPrefetch else { return }
        cancelRadioPreparation()
        if isManual, let request {
            let generation = playbackRequestID
            let controlRevision = radioControlRevision
            Task { [weak self] in
                guard let self, self.playbackRequestID == generation,
                      self.radioControlRevision == controlRevision else { return }
                await self.playRequest(request)
            }
        } else {
            beginRadioPrefetch()
        }
    }

    private func startRadioRequest(
        _ candidates: [UUID], source: PlaybackSource, request: PlaybackRequest,
        queue: PlaybackQueue, prefetch: Bool
    ) async {
        launchRadioRequest(candidates, source: source, request: request, queue: queue, prefetch: prefetch)
        let task = radioPreparationTask
        await withTaskCancellationHandler {
            await task?.value
        } onCancel: {
            task?.cancel()
        }
    }

    private func launchRadioRequest(
        _ candidates: [UUID], source: PlaybackSource, request: PlaybackRequest,
        queue: PlaybackQueue, prefetch: Bool
    ) {
        cancelRadioPreparation()
        let id = UUID()
        radioRequestID = id
        radioTargetID = candidates.first
        radioRequest = request
        radioRequestSource = source
        radioRequestQueue = queue
        radioIsPrefetch = prefetch
        if !prefetch {
            preparationTask?.cancel()
            preparationTask = nil
            playbackRequestID = id
            pendingPlaybackRequestID = id
            pendingFolderSourceID = source.folderID
        }
        radioPreparationTask = Task { [weak self] in
            await self?.prepareRadioCandidates(candidates, source: source, request: request, id: id)
        }
    }

    private func prepareRadioCandidates(
        _ candidates: [UUID], source: PlaybackSource, request: PlaybackRequest, id: UUID
    ) async {
        var failureMessage = L10n.text("Нет доступных аудиофайлов для воспроизведения.")
        for candidateID in candidates {
            guard radioRequestID == id, !Task.isCancelled else { return }
            guard let track = sourceTracks(source).first(where: { $0.id == candidateID }) else { continue }
            radioTargetID = candidateID
            if !radioIsPrefetch || !playbackState.isPlaying { preparingTrackTitle = track.displayName }
            var scopedURL: URL?
            var lease: CachedAudioLease?
            var handle: AudioPreparedTrack?
            do {
                let url: URL
                if case let .folder(queue) = source {
                    guard let access = folderAccess,
                          let entry = queue.entries.first(where: { $0.id == candidateID }) else { continue }
                    // FolderAccess owns coalescing with its browser prefetch and
                    // returns an independent pin for this prepared player.
                    let prepared = try await access.prepare(
                        source: queue.source, entry: entry, priority: .playback
                    )
                    lease = prepared
                    url = prepared.url
                } else {
                    let resource = try resolvedResource(for: track)
                    scopedURL = resource.scopedURL
                    url = resource.url
                    let downloaded = try await mediaAccess.ensureDownloaded(url) { [weak self] in
                        self?.radioRequestID == id && !Task.isCancelled
                    }
                    guard downloaded else { throw PlaybackError.invalidAudioFile }
                }
                try Task.checkCancellation()
                guard radioRequestID == id else { throw CancellationError() }
                let prepared = try await playbackService.prepareTrack(url: url, requestID: id)
                handle = prepared
                try Task.checkCancellation()
                guard radioRequestID == id,
                      sourceTracks(source).contains(where: { $0.id == candidateID }) else {
                    throw CancellationError()
                }
                // Install ownership before schedule: the adapter may commit an
                // already-ended dry handoff synchronously.
                radioPending = PendingRadioTrack(
                    handle: prepared, track: track, source: source, request: request,
                    scopedURL: scopedURL, lease: lease
                )
                scopedURL = nil
                lease = nil
                let atEnd: Bool
                if case .finished = request { atEnd = true } else { atEnd = false }
                try playbackService.scheduleReplacement(prepared, atEnd: atEnd)
                return
            } catch {
                if let handle { playbackService.cancelPreparedTrack(handle) }
                if radioPending?.handle == handle, let pending = radioPending {
                    radioPending = nil
                    releaseRadioResources(pending)
                }
                scopedURL?.stopAccessingSecurityScopedResource()
                if let lease { await folderAccess?.release(lease) }
                guard radioRequestID == id else { return }
                if error is CancellationError || Task.isCancelled {
                    cancelRadioPreparation()
                    return
                }
                // Output failures never label a user's music corrupted.
                if let playbackError = error as? PlaybackError, case .audioUnavailable = playbackError {
                    cancelRadioPreparation()
                    importError = playbackError.localizedDescription
                    return
                }
                failureMessage = L10n.format(
                    "Не удалось воспроизвести «%@». Проверьте файл или повторите импорт.", track.title
                )
            }
        }
        guard radioRequestID == id else { return }
        let wasPrefetch = radioIsPrefetch
        cancelRadioPreparation()
        // A failed speculative candidate does not disturb the playing track or
        // show a premature alert. EOF uses the existing finite fallback search.
        if !wasPrefetch || !playbackState.isPlaying { importError = failureMessage }
    }

    private func commitRadioTrack(_ handle: AudioPreparedTrack) {
        guard let pending = radioPending, pending.handle == handle,
              radioRequestID == handle.requestID else { return }
        // onTrackStarted guarantees the previous reader has stopped. Its grants
        // and the new track's grants are intentionally distinct until this point.
        stopActiveScopedURLIfNeeded()
        activeScopedURL = pending.scopedURL
        activeLease = pending.lease
        activeRadioHandle = handle
        radioPending = nil
        playbackSource = pending.source
        selectedTrackID = pending.track.id
        let explicit: Bool
        if case .selection = pending.request { explicit = true } else { explicit = false }
        if let queue = radioRequestQueue { playbackQueue = queue }
        updatePlaybackQueue(
            startingAt: pending.track,
            restart: !playbackQueue.orderedIDs.contains(pending.track.id)
        )
        recordRadioHistory(pending.track.id, explicit: explicit)
        currentTrackTitle = pending.track.displayName
        nowPlayingArtwork = pending.track.artwork
        if let sectionID = pending.track.section?.id {
            lastPlayedSectionID = sectionID
            defaults.set(sectionID.uuidString, forKey: "lastPlayedSectionID")
        }
        if pendingPlaybackRequestID == handle.requestID { pendingPlaybackRequestID = nil }
        pendingFolderSourceID = nil
        preparingTrackTitle = nil
        radioRequestID = nil
        radioTargetID = nil
        radioRequest = nil
        radioRequestSource = nil
        radioRequestQueue = nil
        radioIsPrefetch = false
        radioPreparationTask = nil
        importError = nil
        synchronizePlaybackPresentation(force: true)
        // Leave the adapter's commit callback before scheduling the next pair.
        Task { [weak self] in self?.beginRadioPrefetch() }
    }

    private func releaseRadioTrack(_ handle: AudioPreparedTrack) {
        if let pending = radioPending, pending.handle == handle {
            radioPending = nil
            releaseRadioResources(pending)
        }
        if activeRadioHandle == handle {
            activeRadioHandle = nil
            stopActiveScopedURLIfNeeded()
        }
    }

    private func recordRadioHistory(_ id: UUID, explicit: Bool) {
        guard playbackMode == .shuffle else {
            radioHistory = []
            radioHistoryPosition = 0
            return
        }
        let available = Set(sourceTracks(playbackSource).map(\.id))
        radioHistory.removeAll { !available.contains($0) }
        if explicit || radioHistory.isEmpty {
            radioHistory = [id]
            radioHistoryPosition = 0
        } else if let index = radioHistory.firstIndex(of: id) {
            radioHistoryPosition = index
        } else {
            radioHistory = Array(radioHistory.prefix(radioHistoryPosition + 1))
            radioHistory.append(id)
            radioHistoryPosition = radioHistory.count - 1
        }
    }

    private func releaseRadioResources(_ track: PendingRadioTrack) {
        track.scopedURL?.stopAccessingSecurityScopedResource()
        if let lease = track.lease, let access = folderAccess {
            Task { await access.release(lease) }
        }
    }

    private func cancelRadioPreparation() {
        guard !isCancellingRadioPreparation else { return }
        isCancellingRadioPreparation = true
        radioControlRevision &+= 1
        defer { isCancellingRadioPreparation = false }
        // Deliver an already audible B before invalidating its request/grants.
        // A UI command can precede the adapter's periodic observation tick.
        playbackService.reconcilePlaybackState()
        let id = radioRequestID
        radioRequestID = nil
        radioTargetID = nil
        radioRequest = nil
        radioRequestSource = nil
        radioRequestQueue = nil
        radioIsPrefetch = false
        radioPreparationTask?.cancel()
        radioPreparationTask = nil
        playbackService.cancelReplacement()
        if let pending = radioPending {
            playbackService.cancelPreparedTrack(pending.handle)
            // A conforming adapter releases synchronously after stopping its
            // inactive node. Retain this fallback for cancelled unopened plans.
            if radioPending?.handle == pending.handle {
                radioPending = nil
                releaseRadioResources(pending)
            }
        }
        if let id, pendingPlaybackRequestID == id {
            pendingPlaybackRequestID = nil
            pendingFolderSourceID = nil
        }
        if id != nil { preparingTrackTitle = nil }
    }

    // MARK: - Remove

    func removeTrack(_ track: PlaylistTrack) {
        let removesSelectedTrack = track.id == selectedTrackID
        do {
            try storageService.removeTrack(track)
            if removesSelectedTrack {
                resetPlayback()
            }
            reloadSections()
        } catch {
            importError = L10n.text("Не удалось удалить трек. Повторите попытку.")
        }
    }

    @discardableResult
    func removeTracks(withIDs trackIDs: Set<UUID>, from section: Playlist) -> Bool {
        guard !isImporting else {
            importError = L10n.text("Дождитесь завершения импорта перед редактированием плейлиста.")
            return false
        }
        guard let currentSection = sections.first(where: { $0.id == section.id }) else {
            importError = L10n.text("Плейлист больше не существует.")
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
            importError = L10n.text("Не удалось удалить выбранные треки. Повторите попытку.")
            return false
        }
    }

    @discardableResult
    func moveTracks(in section: Playlist, from source: IndexSet, to destination: Int) -> Bool {
        guard !isImporting else {
            importError = L10n.text("Дождитесь завершения импорта перед редактированием плейлиста.")
            return false
        }
        guard let currentSection = sections.first(where: { $0.id == section.id }) else {
            importError = L10n.text("Плейлист больше не существует.")
            return false
        }
        var reorderedTracks = tracks(in: currentSection)
        guard source.allSatisfy({ reorderedTracks.indices.contains($0) }),
              (0...reorderedTracks.count).contains(destination) else {
            importError = L10n.text("Список треков изменился. Повторите перемещение.")
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
            importError = L10n.text("Не удалось сохранить порядок треков. Повторите попытку.")
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

    private func setupPlaybackPresentation() {
        _ = nowPlayingService
        // Publish a transport transition before stopping audio can suspend the app.
        // @Published sends in willSet, so use its value instead of reading storage.
        playbackStatusCancellable = playbackState.$isPlaying
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isPlaying in
                guard let self else { return }
                self.synchronizePlaybackPresentation(force: true, isPlaying: isPlaying)
            }
        playbackPresentationCancellable = Publishers.CombineLatest4(
            playbackState.$currentTime, playbackState.$duration,
            playbackState.$isPlaying, playbackState.$isStarting
        )
            .sink { [weak self] _ in
                self?.schedulePlaybackPresentationUpdate()
            }
        radioTimeCancellable = playbackState.$advancesTrackTime
            .removeDuplicates()
            .sink { [weak self] _ in self?.schedulePlaybackPresentationUpdate() }
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

    public func refreshPlaybackPresentation() {
        playbackService.reconcilePlaybackState()
        activityService.retryWhenForegrounded()
        synchronizePlaybackPresentation(force: true)
    }

    private func synchronizePlaybackPresentation(force: Bool = false, isPlaying: Bool? = nil) {
        let duration = playbackState.duration
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
        let time = playbackState.currentTime.isFinite
            ? min(duration, max(0, playbackState.currentTime)) : 0
        let snapshot = PlaybackSnapshot(
            trackID: selectedTrackID,
            title: track.displayName,
            artist: track.displayArtist ?? "",
            duration: duration,
            currentTime: time,
            isPlaying: isPlaying ?? playbackState.isPlaying,
            canPlayPrevious: canPlayPrevious,
            canPlayNext: canPlayNext,
            advancesTrackTime: playbackService.supportsPreparedTransitions
                ? playbackState.advancesTrackTime : (isPlaying ?? playbackState.isPlaying)
        )
        nowPlayingService.update(snapshot, force: force)
        activityService.synchronize(
            snapshot,
            playbackStartDate: Date.now.addingTimeInterval(-time),
            allowStart: UIApplication.shared.applicationState == .active,
            force: force
        )
    }

    private func resetPlayback() {
        invalidatePreparation()
        playbackService.stop()
        stopActiveScopedURLIfNeeded()
        playbackSource = .playlists
        selectedTrackID = nil
        updatePlaybackQueue(restart: true)
        currentTrackTitle = nil
        nowPlayingArtwork = nil
        nowPlayingService.clear()
        activityService.endActivity()
    }

    private func markCorrupted(_ track: PlaylistTrack) {
        do {
            try storageService.setCorrupted(true, for: track)
            reloadSections()
        } catch {
            importError = L10n.text("Не удалось сохранить состояние трека.")
        }
    }

    private func importURLs(_ urls: [URL], to sectionID: UUID) async {
        for url in urls {
            guard !Task.isCancelled else { return }
            do {
                let resource = try mediaAccess.openImportResource(at: url)
                defer { mediaAccess.releaseAccess(to: resource.scopedURL) }
                let files: [URL]
                if let directoryURL = resource.directoryURL {
                    files = await mediaAccess.collectAudioFiles(in: directoryURL)
                } else {
                    files = [url]
                }
                for fileURL in files {
                    guard !Task.isCancelled else { return }
                    guard await downloadFromiCloud(fileURL) else { continue }
                    guard let section = sections.first(where: { $0.id == sectionID }) else {
                        importError = L10n.text("Плейлист для импорта был удалён.")
                        return
                    }
                    await importSingleTrack(at: fileURL, directoryURL: resource.directoryURL, to: section)
                    await Task.yield()
                }
            } catch {
                importError = L10n.format("Нет доступа к «%@». Выберите файл повторно.", url.lastPathComponent)
            }
        }
    }

    private func importSingleTrack(at url: URL, directoryURL: URL?, to section: Playlist) async {
        let sectionID = section.id
        do {
            let metadata = try await mediaAccess.metadata(at: url)
            try Task.checkCancellation()
            guard metadata.duration.isFinite, metadata.duration > 0 else {
                importError = L10n.format("В «%@» нет воспроизводимого аудио.", url.lastPathComponent)
                return
            }
            let bookmark = try mediaAccess.makeBookmark(for: url, directoryURL: directoryURL)
            guard let currentSection = sections.first(where: { $0.id == sectionID }) else { return }
            _ = try storageService.appendTrack(
                title: metadata.title, artist: metadata.artist, url: url, bookmark: bookmark,
                duration: metadata.duration, artwork: metadata.artwork, to: currentSection
            )
        } catch is CancellationError {
            return
        } catch {
            importError = L10n.format("Не удалось импортировать «%@». Проверьте формат и доступ к файлу.", url.lastPathComponent)
        }
    }

    private func downloadFromiCloud(_ url: URL, requestID: UUID? = nil, modeRevision: UInt? = nil) async -> Bool {
        do {
            return try await mediaAccess.ensureDownloaded(url) { [weak self] in
                guard let self else { return false }
                return !Task.isCancelled && (requestID == nil || requestID == self.playbackRequestID)
                    && (modeRevision == nil || modeRevision == self.playbackModeRevision)
            }
        } catch {
            importError = error.localizedDescription
            return false
        }
    }

    private func resolvedResource(for track: PlaylistTrack) throws -> (url: URL, scopedURL: URL?) {
        let resource = try mediaAccess.resolve(bookmark: track.bookmark, filePath: track.filePath)
        do {
            if let bookmark = resource.refreshedBookmark {
                try storageService.updateBookmark(for: track, bookmark: bookmark, url: resource.url)
            }
            return (resource.url, resource.scopedURL)
        } catch {
            mediaAccess.releaseAccess(to: resource.scopedURL)
            throw error
        }
    }

    private func stopActiveScopedURLIfNeeded() {
        if let lease = activeLease, let access = folderAccess {
            activeLease = nil
            Task { await access.release(lease) }
        }
        activeScopedURL?.stopAccessingSecurityScopedResource()
        activeScopedURL = nil
    }

    var selectedTrack: PlaylistTrack? {
        let tracks = sourceTracks(playbackSource)
        guard let selectedTrackID else { return tracks.first }
        return tracks.first(where: { $0.id == selectedTrackID })
    }
}
