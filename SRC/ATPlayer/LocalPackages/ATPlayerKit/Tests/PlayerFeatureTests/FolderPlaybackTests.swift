import FolderDomain
import Foundation
import LibraryDomain
import PlaybackDomain
@testable import PlayerFeature
import XCTest

@MainActor
final class FolderPlaybackTests: XCTestCase {
    private let eventTimeout: TimeInterval = 3

    func testCurrentLevelSnapshotExcludesDirectoriesAndSurvivesFurtherBrowsing() async throws {
        let fixture = try FolderFixture()
        defer { fixture.cleanup() }
        var visibleEntries = fixture.entries
        await fixture.model.playFolder(source: fixture.source, entries: visibleEntries, selectedID: fixture.audioEntries[0].id)
        fixture.model.seek(to: 3)

        visibleEntries = [FolderFixture.entry(name: "other.wav", relativePath: "other/other.wav", kind: .audio)]
        fixture.folders.listingEntries = visibleEntries
        _ = try await fixture.folders.list(source: fixture.source, relativePath: "other")
        fixture.model.reloadSections()
        XCTAssertEqual(fixture.model.selectedTrackID, fixture.audioEntries[0].id)
        XCTAssertEqual(fixture.audio.state.currentTime, 3)
        XCTAssertTrue(fixture.audio.state.isPlaying)

        await fixture.model.performPlaybackCommand(.next)
        XCTAssertEqual(fixture.model.selectedTrackID, fixture.audioEntries[1].id)
        await fixture.model.performPlaybackCommand(.next)
        XCTAssertEqual(fixture.model.selectedTrackID, fixture.audioEntries[2].id)
        XCTAssertFalse(fixture.model.canPlayNext)
        let ended = expectation(description: "Current directory ends without entering another source")
        fixture.activity.onEnd = { ended.fulfill() }
        fixture.audio.finish()
        await fulfillment(of: [ended], timeout: eventTimeout)

        XCTAssertFalse(fixture.audio.state.isPlaying)
        XCTAssertEqual(fixture.folders.preparedIDs, fixture.audioEntries.map(\.id))
        XCTAssertTrue(fixture.media.resolvedPaths.isEmpty, "Folder EOF must not enter persisted playlists")
        XCTAssertEqual(fixture.storage.tracks.map(\.id), [fixture.playlistTrack.id])
    }

    func testRepeatPlaylistWrapsWithinFolderAudioOnly() async throws {
        let fixture = try FolderFixture()
        defer { fixture.cleanup() }
        fixture.setMode(.repeatPlaylist)
        let first = fixture.audioEntries[0]
        let last = fixture.audioEntries[2]
        await fixture.model.playFolder(source: fixture.source, entries: fixture.entries, selectedID: last.id)
        let wrapped = expectation(description: "Folder EOF wraps to first audio")
        fixture.audio.onLoad = { url in
            if url == FolderAccessDouble.localURL(for: first.id) { wrapped.fulfill() }
        }
        fixture.audio.finish()
        await fulfillment(of: [wrapped], timeout: eventTimeout)
        XCTAssertEqual(fixture.model.selectedTrackID, first.id)

        await fixture.model.performPlaybackCommand(.previous)
        XCTAssertEqual(fixture.model.selectedTrackID, last.id)
        XCTAssertEqual(fixture.folders.preparedIDs, [last.id, first.id, last.id])
        XCTAssertTrue(fixture.media.resolvedPaths.isEmpty)
    }

    func testFolderRepeatOneRestartsSameFileAndManualNextAdvances() async throws {
        let fixture = try FolderFixture()
        defer { fixture.cleanup() }
        fixture.setMode(.repeatOne)
        let first = fixture.audioEntries[0]
        await fixture.model.playFolder(source: fixture.source, entries: fixture.entries, selectedID: first.id)
        let repeated = expectation(description: "Folder repeat-one restarts the selected file")
        fixture.audio.onLoad = { url in
            if url == FolderAccessDouble.localURL(for: first.id) { repeated.fulfill() }
        }
        fixture.audio.finish()
        await fulfillment(of: [repeated], timeout: eventTimeout)
        XCTAssertEqual(fixture.model.selectedTrackID, first.id)
        XCTAssertEqual(fixture.audio.state.currentTime, 0)

        await fixture.model.performPlaybackCommand(.next)
        XCTAssertEqual(fixture.model.selectedTrackID, fixture.audioEntries[1].id)
        XCTAssertTrue(fixture.media.resolvedPaths.isEmpty)
    }

    func testFolderShuffleIsFiniteAndNeverUsesPlaylistOrDirectoryEntries() async throws {
        let fixture = try FolderFixture()
        defer { fixture.cleanup() }
        await fixture.model.playFolder(source: fixture.source, entries: fixture.entries, selectedID: fixture.audioEntries[0].id)
        fixture.setMode(.shuffle)
        var visited = [fixture.audioEntries[0].id]
        for _ in 1..<fixture.audioEntries.count {
            await fixture.model.performPlaybackCommand(.next)
            let selected = try XCTUnwrap(fixture.model.selectedTrackID)
            XCTAssertFalse(visited.contains(selected))
            visited.append(selected)
        }
        XCTAssertEqual(Set(visited), Set(fixture.audioEntries.map(\.id)))
        XCTAssertFalse(fixture.model.canPlayNext)
        await fixture.model.performPlaybackCommand(.next)
        XCTAssertEqual(fixture.folders.preparedIDs.count, fixture.audioEntries.count)
        await fixture.model.performPlaybackCommand(.previous)
        XCTAssertEqual(fixture.model.selectedTrackID, visited[1])
        XCTAssertTrue(fixture.media.resolvedPaths.isEmpty)
    }

    func testPauseRejectsLatePreparedFileAndReleasesItsLease() async throws {
        let fixture = try FolderFixture()
        defer { fixture.cleanup() }
        await fixture.model.play(track: fixture.playlistTrack)
        let entry = fixture.audioEntries[0]
        fixture.folders.delayedID = entry.id
        let entered = expectation(description: "File preparation is suspended")
        fixture.folders.onPreparationStarted = { entered.fulfill() }
        let request = Task {
            await fixture.model.playFolder(source: fixture.source, entries: fixture.entries, selectedID: entry.id)
        }
        defer { request.cancel(); fixture.folders.finishDelayedPreparation() }
        await fulfillment(of: [entered], timeout: eventTimeout)

        await fixture.model.performPlaybackCommand(.pause)
        fixture.folders.finishDelayedPreparation()
        await request.value

        XCTAssertEqual(fixture.model.selectedTrackID, fixture.playlistTrack.id)
        XCTAssertFalse(fixture.audio.state.isPlaying)
        XCTAssertFalse(fixture.audio.state.isStarting)
        XCTAssertNil(fixture.model.preparingTrackTitle)
        XCTAssertEqual(fixture.folders.releasedLeases.map(\.entryID), [entry.id])
        XCTAssertEqual(fixture.audio.loadedURLs.map(\.path), [fixture.playlistTrack.filePath])
    }

    func testSwitchingToPlaylistRejectsLateFolderResultAndReleasesAfterAudioStops() async throws {
        let fixture = try FolderFixture()
        defer { fixture.cleanup() }
        let first = fixture.audioEntries[0]
        let delayed = fixture.audioEntries[1]
        await fixture.model.playFolder(source: fixture.source, entries: fixture.entries, selectedID: first.id)
        fixture.folders.delayedID = delayed.id
        let entered = expectation(description: "Second folder file is preparing")
        fixture.folders.onPreparationStarted = { entered.fulfill() }
        let request = Task {
            await fixture.model.playFolder(source: fixture.source, entries: fixture.entries, selectedID: delayed.id)
        }
        defer { request.cancel(); fixture.folders.finishDelayedPreparation() }
        await fulfillment(of: [entered], timeout: eventTimeout)

        let activeReleased = expectation(description: "Old folder lease is released")
        fixture.folders.onRelease = { lease in
            XCTAssertNotEqual(fixture.audio.currentURL, lease.url, "A lease cannot be released while its file is playing")
            if lease.entryID == first.id { activeReleased.fulfill() }
        }
        await fixture.model.play(track: fixture.playlistTrack)
        fixture.folders.finishDelayedPreparation()
        await request.value
        await fulfillment(of: [activeReleased], timeout: eventTimeout)

        XCTAssertEqual(fixture.model.selectedTrackID, fixture.playlistTrack.id)
        XCTAssertTrue(fixture.audio.state.isPlaying)
        XCTAssertEqual(Set(fixture.folders.releasedLeases.map(\.entryID)), [first.id, delayed.id])
        XCTAssertEqual(fixture.audio.loadedURLs, [FolderAccessDouble.localURL(for: first.id), URL(fileURLWithPath: fixture.playlistTrack.filePath)])
    }

    func testFailedNewFolderSelectionPreservesPreviouslyPlayingPlaylist() async throws {
        let fixture = try FolderFixture()
        defer { fixture.cleanup() }
        await fixture.model.play(track: fixture.playlistTrack)
        fixture.model.seek(to: 5)
        fixture.folders.unavailableIDs = Set(fixture.audioEntries.map(\.id))

        await fixture.model.playFolder(source: fixture.source, entries: fixture.entries, selectedID: fixture.audioEntries[0].id)

        XCTAssertEqual(fixture.model.selectedTrackID, fixture.playlistTrack.id)
        XCTAssertEqual(fixture.audio.state.currentTime, 5)
        XCTAssertTrue(fixture.audio.state.isPlaying)
        XCTAssertEqual(fixture.folders.preparedIDs, fixture.audioEntries.map(\.id))
        XCTAssertEqual(fixture.audio.loadedURLs.map(\.path), [fixture.playlistTrack.filePath])
        XCTAssertEqual(fixture.model.importError, FolderAccessError.unavailable.localizedDescription,
                       "Folder recovery guidance must not be replaced with playlist-import instructions")
    }

    func testAllFolderFailuresExhaustOneFiniteQueueWithoutPlaylistFallback() async throws {
        let fixture = try FolderFixture()
        defer { fixture.cleanup() }
        fixture.setMode(.repeatPlaylist)
        await fixture.model.playFolder(source: fixture.source, entries: fixture.entries, selectedID: fixture.audioEntries[2].id)
        fixture.folders.preparedIDs.removeAll()
        fixture.folders.unavailableIDs = Set(fixture.audioEntries.map(\.id))

        await fixture.model.performPlaybackCommand(.next)

        XCTAssertEqual(fixture.folders.preparedIDs, fixture.audioEntries.map(\.id))
        XCTAssertNil(fixture.model.selectedTrackID)
        XCTAssertFalse(fixture.audio.state.isPlaying)
        XCTAssertNotNil(fixture.model.importError)
        XCTAssertTrue(fixture.media.resolvedPaths.isEmpty)
    }

    func testRemovingPendingRootInvalidatesPreparationButKeepsOldPlaylistPlaying() async throws {
        let fixture = try FolderFixture()
        defer { fixture.cleanup() }
        await fixture.model.play(track: fixture.playlistTrack)
        let entry = fixture.audioEntries[0]
        fixture.folders.delayedID = entry.id
        let entered = expectation(description: "Removed root has pending preparation")
        fixture.folders.onPreparationStarted = { entered.fulfill() }
        let request = Task {
            await fixture.model.playFolder(source: fixture.source, entries: fixture.entries, selectedID: entry.id)
        }
        defer { request.cancel(); fixture.folders.finishDelayedPreparation() }
        await fulfillment(of: [entered], timeout: eventTimeout)

        fixture.model.removeFolderSource(id: fixture.source.id)
        fixture.folders.finishDelayedPreparation()
        await request.value

        XCTAssertEqual(fixture.model.selectedTrackID, fixture.playlistTrack.id)
        XCTAssertTrue(fixture.audio.state.isPlaying)
        XCTAssertEqual(fixture.folders.releasedLeases.map(\.entryID), [entry.id])
        XCTAssertEqual(fixture.audio.loadedURLs.count, 1)
        XCTAssertNil(fixture.model.preparingTrackTitle)
    }

    func testRemovingActiveRootStopsAudioAndInvalidatesPendingFile() async throws {
        let fixture = try FolderFixture()
        defer { fixture.cleanup() }
        let first = fixture.audioEntries[0]
        let delayed = fixture.audioEntries[1]
        await fixture.model.playFolder(source: fixture.source, entries: fixture.entries, selectedID: first.id)
        fixture.folders.delayedID = delayed.id
        let entered = expectation(description: "Next file is preparing when root is removed")
        fixture.folders.onPreparationStarted = { entered.fulfill() }
        let request = Task { await fixture.model.performPlaybackCommand(.next) }
        defer { request.cancel(); fixture.folders.finishDelayedPreparation() }
        await fulfillment(of: [entered], timeout: eventTimeout)

        let activeReleased = expectation(description: "Removed root releases its active file")
        fixture.folders.onRelease = { lease in
            XCTAssertNil(fixture.audio.currentURL, "Stop must precede release after root removal")
            if lease.entryID == first.id { activeReleased.fulfill() }
        }
        fixture.model.removeFolderSource(id: fixture.source.id)
        fixture.folders.finishDelayedPreparation()
        await request.value
        await fulfillment(of: [activeReleased], timeout: eventTimeout)

        XCTAssertNil(fixture.model.selectedTrackID)
        XCTAssertFalse(fixture.audio.state.isPlaying)
        XCTAssertEqual(fixture.audio.loadedURLs, [FolderAccessDouble.localURL(for: first.id)])
        XCTAssertEqual(Set(fixture.folders.releasedLeases.map(\.entryID)), [first.id, delayed.id])
        XCTAssertTrue(fixture.media.resolvedPaths.isEmpty)
    }
}

@MainActor
private final class FolderFixture {
    let suiteName = "ATPlayer.FolderPlaybackTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let source = FolderSource(name: "Music", bookmark: Data())
    let entries: [FolderEntry]
    var audioEntries: [FolderEntry] { entries.filter { $0.kind == .audio } }
    let playlistTrack: PlaylistTrack
    let storage: ReadOnlyPlaylistDouble
    let audio = FolderAudioDouble()
    let media = FolderPlaylistMediaDouble()
    let folders = FolderAccessDouble()
    let activity = FolderActivityDouble()
    let nowPlaying = FolderNowPlayingDouble()
    lazy var model = ATPlayerViewModel(
        storage: storage, audio: audio, activity: activity, nowPlaying: nowPlaying,
        mediaAccess: media, defaults: defaults, folderAccess: folders
    )

    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        entries = [
            Self.entry(name: "Nested", relativePath: "album/Nested", kind: .directory),
            Self.entry(name: "1.wav", relativePath: "album/1.wav", kind: .audio),
            Self.entry(name: "2.wav", relativePath: "album/2.wav", kind: .audio),
            Self.entry(name: "3.wav", relativePath: "album/3.wav", kind: .audio)
        ]
        playlistTrack = PlaylistTrack(title: "Saved", artist: "", filePath: "/playlist/saved.wav", bookmark: Data(), duration: 10, order: 0)
        storage = ReadOnlyPlaylistDouble(track: playlistTrack)
    }

    static func entry(name: String, relativePath: String, kind: FolderEntry.Kind) -> FolderEntry {
        FolderEntry(id: UUID(), name: name, relativePath: relativePath, kind: kind)
    }

    func setMode(_ mode: PlaybackMode) {
        for _ in PlaybackMode.allCases where model.playbackMode != mode { model.cyclePlaybackMode() }
        XCTAssertEqual(model.playbackMode, mode)
    }

    func cleanup() {
        folders.onRelease = nil
        folders.onPreparationStarted = nil
        folders.finishDelayedPreparation()
        audio.onLoad = nil
        audio.onTrackFinished = nil
        activity.onEnd = nil
        model.removeFolderSource(id: source.id)
        audio.stop()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class FolderAccessDouble: FolderAccessing {
    var preparedIDs: [UUID] = []
    var releasedLeases: [CachedAudioLease] = []
    var unavailableIDs: Set<UUID> = []
    var delayedID: UUID?
    var listingEntries: [FolderEntry] = []
    var onPreparationStarted: (() -> Void)?
    var onRelease: ((CachedAudioLease) -> Void)?
    private var continuation: CheckedContinuation<CachedAudioLease, Never>?
    private var delayedLease: CachedAudioLease?

    static func localURL(for entryID: UUID) -> URL {
        URL(fileURLWithPath: "/temporary-audio/\(entryID.uuidString).wav")
    }

    func makeSource(at url: URL) async throws -> FolderSource {
        FolderSource(name: url.lastPathComponent, bookmark: Data(url.absoluteString.utf8))
    }

    func list(source: FolderSource, relativePath: String) async throws -> FolderListing {
        FolderListing(source: source, relativePath: relativePath, entries: listingEntries)
    }

    func prepare(source: FolderSource, entry: FolderEntry, priority: FolderPreparationPriority) async throws -> CachedAudioLease {
        preparedIDs.append(entry.id)
        if unavailableIDs.contains(entry.id) { throw FolderAccessError.unavailable }
        let lease = CachedAudioLease(url: Self.localURL(for: entry.id), entryID: entry.id)
        if entry.id == delayedID {
            // A provider may finish after cancellation; the caller still owns cleanup.
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                delayedLease = lease
                onPreparationStarted?()
            }
        }
        return lease
    }

    func finishDelayedPreparation() {
        guard let continuation, let lease = delayedLease else { return }
        self.continuation = nil
        delayedLease = nil
        continuation.resume(returning: lease)
    }

    func release(_ lease: CachedAudioLease) async {
        XCTAssertFalse(releasedLeases.contains { $0.id == lease.id }, "A lease must be released exactly once")
        releasedLeases.append(lease)
        onRelease?(lease)
    }

    func forget(sourceID: UUID) async {}
}

@MainActor
private final class FolderAudioDouble: AudioPlaying {
    let state = AudioPlaybackState()
    var onTrackFinished: (() -> Void)?
    var onLoad: ((URL) -> Void)?
    var loadedURLs: [URL] = []
    var currentURL: URL?

    func loadAndPlay(url: URL) async throws {
        loadedURLs.append(url)
        currentURL = url
        state.duration = 10
        state.currentTime = 0
        state.isPlaying = true
        onLoad?(url)
    }

    func play() -> Task<Void, Error>? { state.isPlaying = currentURL != nil; return nil }
    func pauseByUser() { pause() }
    func pause() { state.isPlaying = false; state.isStarting = false }
    func stop() {
        pause()
        currentURL = nil
        state.currentTime = 0
        state.duration = 0
    }
    func seek(to time: TimeInterval) { state.currentTime = time }
    func finish() {
        state.currentTime = state.duration
        state.isPlaying = false
        onTrackFinished?()
    }
}

@MainActor
private final class FolderPlaylistMediaDouble: MediaResourceAccess {
    var resolvedPaths: [String] = []
    func openImportResource(at url: URL) throws -> ImportMediaResource {
        ImportMediaResource(url: url, directoryURL: nil, scopedURL: nil)
    }
    func releaseAccess(to scopedURL: URL?) {}
    func makeBookmark(for url: URL, directoryURL: URL?) throws -> Data { Data(url.absoluteString.utf8) }
    func resolve(bookmark: Data, filePath: String) throws -> ResolvedMediaResource {
        resolvedPaths.append(filePath)
        return ResolvedMediaResource(url: URL(fileURLWithPath: filePath), scopedURL: nil, refreshedBookmark: nil)
    }
    func ensureDownloaded(_ url: URL, isCurrent: @escaping @MainActor () -> Bool) async throws -> Bool { isCurrent() }
    func metadata(at url: URL) async throws -> MediaMetadata {
        MediaMetadata(title: url.lastPathComponent, artist: "", duration: 10, artwork: nil)
    }
    func collectAudioFiles(in directoryURL: URL) async -> [URL] { [] }
}

@MainActor
private final class FolderNowPlayingDouble: NowPlayingPresenting {
    var handleCommand: (@MainActor @Sendable (PlaybackCommand) -> Void)?
    func update(_ snapshot: PlaybackSnapshot, force: Bool) {}
    func clear() {}
}

@MainActor
private final class FolderActivityDouble: ActivityPresenting {
    var onEnd: (() -> Void)?
    func endAllStaleActivities() {}
    func synchronize(_ snapshot: PlaybackSnapshot, playbackStartDate: Date, allowStart: Bool, force: Bool) {}
    func retryWhenForegrounded() {}
    func endActivity() {
        let callback = onEnd
        onEnd = nil
        callback?()
    }
}

@MainActor
private final class ReadOnlyPlaylistDouble: PlaylistStoring {
    private enum Failure: Error { case unexpectedMutation }
    private let section: Playlist
    var tracks: [PlaylistTrack] { section.tracks }
    init(track: PlaylistTrack) { section = Playlist(name: "Saved", order: 0, tracks: [track]) }
    func fetchSections() throws -> [Playlist] { [section] }
    func ensureDefaultSection() throws -> Playlist { section }
    func sortedTracks(in section: Playlist) -> [PlaylistTrack] { section.tracks }
    func createSection(name: String) throws -> Playlist { try unexpectedMutation() }
    func removeSection(_ section: Playlist) throws { try unexpectedMutation() as Void }
    func renameSection(_ section: Playlist, to name: String) throws { try unexpectedMutation() as Void }
    func appendTrack(title: String, artist: String, url: URL, bookmark: Data, duration: Double, artwork: Data?, to section: Playlist) throws -> PlaylistTrack {
        try unexpectedMutation()
    }
    func setCorrupted(_ isCorrupted: Bool, for track: PlaylistTrack) throws { try unexpectedMutation() as Void }
    func updateBookmark(for track: PlaylistTrack, bookmark: Data, url: URL) throws { try unexpectedMutation() as Void }
    func removeTrack(_ track: PlaylistTrack) throws { try unexpectedMutation() as Void }
    func removeTracks(withIDs trackIDs: Set<UUID>, from section: Playlist) throws { try unexpectedMutation() as Void }
    func setTrackOrder(_ trackIDs: [UUID], in section: Playlist) throws { try unexpectedMutation() as Void }
    func setSectionOrder(_ sectionIDs: [UUID]) throws { try unexpectedMutation() as Void }
    private func unexpectedMutation<T>() throws -> T {
        XCTFail("Folder playback must not mutate persisted playlists")
        throw Failure.unexpectedMutation
    }
}
