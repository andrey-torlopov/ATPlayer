import Foundation
import LibraryDomain
import PlaybackDomain
@testable import PlayerFeature
import XCTest

@MainActor
final class PlaybackSessionTests: XCTestCase {
    private let eventTimeout: TimeInterval = 3

    func testOrdinaryPlaybackCrossesPlaylistBoundaryInBothDirections() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        await fixture.model.play(track: fixture.first[2])

        let advanced = expectation(description: "EOF starts the next playlist")
        fixture.audio.onLoad = { url in
            if url.path == fixture.second[0].filePath { advanced.fulfill() }
        }
        fixture.audio.finishTrack()
        await fulfillment(of: [advanced], timeout: eventTimeout)

        XCTAssertEqual(fixture.model.selectedTrackID, fixture.second[0].id)
        XCTAssertTrue(fixture.audio.state.isPlaying)
        await fixture.model.performPlaybackCommand(.previous)
        XCTAssertEqual(fixture.model.selectedTrackID, fixture.first[2].id)

        await fixture.model.play(track: fixture.first[0])
        XCTAssertFalse(fixture.model.canPlayPrevious)
        await fixture.model.performPlaybackCommand(.previous)
        XCTAssertEqual(fixture.model.selectedTrackID, fixture.first[0].id)
    }

    func testOrdinaryPlaybackStopsAtLibraryEndWithoutLosingSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        await fixture.model.play(track: fixture.second[1])
        let loadsBeforeEOF = fixture.audio.loadedURLs.count
        let ended = expectation(description: "Terminal EOF ends the activity")
        fixture.activity.onEnd = { ended.fulfill() }

        fixture.audio.finishTrack()
        await fulfillment(of: [ended], timeout: eventTimeout)

        XCTAssertEqual(fixture.model.selectedTrackID, fixture.second[1].id)
        XCTAssertEqual(fixture.audio.loadedURLs.count, loadsBeforeEOF)
        XCTAssertFalse(fixture.audio.state.isPlaying)
        XCTAssertFalse(fixture.model.canPlayNext)
    }

    func testPlaylistRepeatWrapsWithoutEnteringOtherPlaylists() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.setMode(.repeatPlaylist)
        await fixture.model.play(track: fixture.first[2])
        let wrapped = expectation(description: "EOF wraps to the same playlist")
        fixture.audio.onLoad = { url in
            if url.path == fixture.first[0].filePath { wrapped.fulfill() }
        }

        fixture.audio.finishTrack()
        await fulfillment(of: [wrapped], timeout: eventTimeout)
        XCTAssertEqual(fixture.model.selectedTrackID, fixture.first[0].id)
        await fixture.model.performPlaybackCommand(.previous)
        XCTAssertEqual(fixture.model.selectedTrackID, fixture.first[2].id)
        XCTAssertTrue(fixture.audio.loadedURLs.allSatisfy { url in
            fixture.first.contains { $0.filePath == url.path }
        })
    }

    func testRepeatOneRestartsOnEOFButManualNextAdvances() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.setMode(.repeatOne)
        await fixture.model.play(track: fixture.first[1])
        let repeated = expectation(description: "EOF reloads the same track")
        fixture.audio.onLoad = { url in
            if url.path == fixture.first[1].filePath { repeated.fulfill() }
        }

        fixture.audio.finishTrack()
        await fulfillment(of: [repeated], timeout: eventTimeout)
        XCTAssertEqual(fixture.model.selectedTrackID, fixture.first[1].id)
        XCTAssertEqual(fixture.audio.state.currentTime, 0)
        XCTAssertTrue(fixture.audio.state.isPlaying)

        await fixture.model.performPlaybackCommand(.next)
        XCTAssertEqual(fixture.model.selectedTrackID, fixture.first[2].id)
    }

    func testShuffleIsFiniteUniqueScopedAndReversible() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        await fixture.model.play(track: fixture.first[0])
        fixture.setMode(.shuffle)
        var visited = [fixture.first[0].id]
        for _ in 1..<fixture.first.count {
            await fixture.model.performPlaybackCommand(.next)
            let selected = try XCTUnwrap(fixture.model.selectedTrackID)
            XCTAssertFalse(visited.contains(selected), "Shuffle repeated before exhausting the playlist")
            visited.append(selected)
        }
        XCTAssertEqual(Set(visited), Set(fixture.first.map(\.id)))
        XCTAssertFalse(fixture.model.canPlayNext)
        let ended = expectation(description: "Shuffle stops after one pass")
        fixture.activity.onEnd = { ended.fulfill() }
        fixture.audio.finishTrack()
        await fulfillment(of: [ended], timeout: eventTimeout)
        XCTAssertFalse(fixture.audio.state.isPlaying)

        await fixture.model.performPlaybackCommand(.previous)
        XCTAssertEqual(fixture.model.selectedTrackID, visited[1])
    }

    func testModeChangesPreserveSelectionPositionAndPauseState() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        await fixture.model.play(track: fixture.first[1])
        fixture.model.seek(to: 4)
        let initialLoads = fixture.audio.loadedURLs.count
        for expected in [PlaybackMode.repeatPlaylist, .shuffle, .repeatOne, .off] {
            fixture.model.cyclePlaybackMode()
            XCTAssertEqual(fixture.model.playbackMode, expected)
            XCTAssertEqual(fixture.model.selectedTrackID, fixture.first[1].id)
            XCTAssertEqual(fixture.audio.state.currentTime, 4)
            XCTAssertTrue(fixture.audio.state.isPlaying)
            XCTAssertEqual(fixture.audio.loadedURLs.count, initialLoads)
        }
        await fixture.model.performPlaybackCommand(.pause)
        for expected in [PlaybackMode.repeatPlaylist, .shuffle, .repeatOne, .off] {
            fixture.model.cyclePlaybackMode()
            XCTAssertEqual(fixture.model.playbackMode, expected)
            XCTAssertEqual(fixture.audio.state.currentTime, 4)
            XCTAssertFalse(fixture.audio.state.isPlaying)
            XCTAssertFalse(fixture.audio.state.isStarting)
        }
    }

    func testRefreshingPresentationPreservesPlaybackAndPauseState() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        await fixture.model.play(track: fixture.first[1])
        fixture.model.seek(to: 4)
        let loadedBeforeRefresh = fixture.audio.loadedURLs

        for shouldPlay in [true, false] {
            if !shouldPlay { await fixture.model.performPlaybackCommand(.pause) }
            let updatesBeforeRefresh = fixture.activity.forcedUpdateCount

            fixture.model.refreshPlaybackPresentation()

            XCTAssertEqual(fixture.audio.loadedURLs, loadedBeforeRefresh,
                           "Changing the presentation language must not reload the audio file.")
            XCTAssertEqual(fixture.model.selectedTrackID, fixture.first[1].id)
            XCTAssertEqual(fixture.audio.state.currentTime, 4)
            XCTAssertEqual(fixture.audio.state.isPlaying, shouldPlay)
            XCTAssertEqual(fixture.activity.forcedUpdateCount, updatesBeforeRefresh + 1)
            XCTAssertEqual(fixture.activity.snapshot?.currentTime, 4)
            XCTAssertEqual(fixture.activity.snapshot?.isPlaying, shouldPlay)
            XCTAssertEqual(fixture.nowPlaying.snapshot, fixture.activity.snapshot)
        }
    }

    func testExternalPauseImmediatelyUpdatesSystemPresentationWithoutForegroundRefresh() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        await fixture.model.play(track: fixture.first[1])
        fixture.audio.state.currentTime = 4

        // An interruption stops audio independently of a UI or remote command.
        // Deliver the pause before another actor turn or a foreground refresh.
        fixture.audio.state.isPlaying = false

        XCTAssertEqual(fixture.activity.snapshot?.isPlaying, false)
        XCTAssertEqual(fixture.activity.snapshot?.currentTime, 4)
        XCTAssertEqual(fixture.activity.snapshot?.trackID, fixture.first[1].id)
        XCTAssertEqual(fixture.nowPlaying.snapshot, fixture.activity.snapshot)
    }

    func testRemotePlayAndToggleReconcileStoppedOutputBeforeCheckingCachedState() async throws {
        for command in [PlaybackCommand.play, .toggle] {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            await fixture.model.play(track: fixture.first[1])
            let loadedURLs = fixture.audio.loadedURLs
            fixture.audio.isStoppedExternally = true

            await fixture.model.performPlaybackCommand(command)

            XCTAssertEqual(fixture.audio.resumeCalls, 1,
                           "An explicit resume must inspect the output before trusting cached isPlaying.")
            XCTAssertFalse(fixture.audio.isStoppedExternally)
            XCTAssertTrue(fixture.audio.state.isPlaying)
            XCTAssertEqual(fixture.audio.loadedURLs, loadedURLs)
            XCTAssertEqual(fixture.activity.snapshot?.isPlaying, true)
            XCTAssertEqual(fixture.nowPlaying.snapshot, fixture.activity.snapshot)
        }
    }

    func testExternalPauseDuringDelayedTrackPreparationImmediatelyUpdatesCurrentTrackPresentation() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        await fixture.model.play(track: fixture.first[0])
        fixture.audio.state.currentTime = 4
        fixture.media.delayedPath = fixture.first[1].filePath
        let downloading = expectation(description: "Replacement waits while the current track plays")
        fixture.media.onDownloadStarted = { downloading.fulfill() }
        let request = Task { await fixture.model.play(track: fixture.first[1]) }
        defer {
            request.cancel()
            fixture.media.releaseDownload()
        }

        await fulfillment(of: [downloading], timeout: eventTimeout)
        XCTAssertTrue(fixture.audio.state.isPlaying)
        XCTAssertEqual(fixture.model.preparingTrackTitle, fixture.first[1].displayName)

        // A phone call interrupts the old track even while another file downloads.
        fixture.audio.state.isPlaying = false

        XCTAssertEqual(fixture.activity.snapshot?.isPlaying, false)
        XCTAssertEqual(fixture.activity.snapshot?.currentTime, 4)
        XCTAssertEqual(fixture.activity.snapshot?.trackID, fixture.first[0].id)
        XCTAssertEqual(fixture.nowPlaying.snapshot, fixture.activity.snapshot)

        request.cancel()
        fixture.media.releaseDownload()
        await request.value
        XCTAssertEqual(fixture.audio.loadedURLs.map(\.path), [fixture.first[0].filePath])
        XCTAssertNil(fixture.model.preparingTrackTitle)
    }

    func testPauseInvalidatesDelayedDownloadWithoutReplacingCurrentTrack() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        await fixture.model.play(track: fixture.first[0])
        fixture.media.delayedPath = fixture.first[1].filePath
        let downloading = expectation(description: "Replacement is waiting for its download")
        fixture.media.onDownloadStarted = { downloading.fulfill() }
        let request = Task { await fixture.model.play(track: fixture.first[1]) }
        defer {
            request.cancel()
            fixture.media.releaseDownload()
        }

        await fulfillment(of: [downloading], timeout: eventTimeout)
        await fixture.model.performPlaybackCommand(.pause)
        fixture.media.releaseDownload()
        await request.value

        XCTAssertEqual(fixture.model.selectedTrackID, fixture.first[0].id)
        XCTAssertEqual(fixture.audio.loadedURLs.map(\.path), [fixture.first[0].filePath])
        XCTAssertFalse(fixture.audio.state.isPlaying)
        XCTAssertFalse(fixture.audio.state.isStarting)
        XCTAssertNil(fixture.model.importError)
    }

    func testUnavailableSourcesExhaustFinitePlaylistAndCanRecover() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.setMode(.repeatPlaylist)
        await fixture.model.play(track: fixture.first[2])
        fixture.media.unavailablePaths = Set(fixture.first.map(\.filePath))
        fixture.media.resolvedPaths.removeAll()

        await fixture.model.performPlaybackCommand(.next)

        XCTAssertEqual(fixture.media.resolvedPaths, fixture.first.map(\.filePath),
                       "Repeated playback must try each candidate once and stay in its playlist")
        XCTAssertNil(fixture.model.selectedTrackID)
        XCTAssertFalse(fixture.audio.state.isPlaying)
        XCTAssertNotNil(fixture.model.importError)

        fixture.media.unavailablePaths.remove(fixture.first[0].filePath)
        await fixture.model.performPlaybackCommand(.play)
        XCTAssertEqual(fixture.model.selectedTrackID, fixture.first[0].id)
        XCTAssertTrue(fixture.audio.state.isPlaying)
        XCTAssertNil(fixture.model.importError)
    }

    func testInvalidAudioIsMarkedAndSkippedWithinRepeatedPlaylist() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.setMode(.repeatPlaylist)
        fixture.audio.invalidPaths = [fixture.first[0].filePath]

        await fixture.model.play(track: fixture.first[0])

        XCTAssertTrue(fixture.first[0].isCorrupted)
        XCTAssertEqual(fixture.model.selectedTrackID, fixture.first[1].id)
        XCTAssertTrue(fixture.audio.state.isPlaying)
        XCTAssertNil(fixture.model.importError)
    }

    func testPlaybackPreferencesAndLastPlaylistRestoreFromInjectedDefaults() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        await fixture.model.play(track: fixture.second[0])
        for mode in [PlaybackMode.repeatPlaylist, .shuffle, .repeatOne, .off] {
            fixture.setMode(mode)
            let restored = fixture.makeModel()
            XCTAssertEqual(fixture.defaults.string(forKey: "playbackMode"), mode.rawValue)
            XCTAssertEqual(restored.playbackMode, mode)
            XCTAssertEqual(restored.lastPlayedSectionID, fixture.second[0].section?.id)
        }
    }

    func testPlaylistMoveKeepsAudioPositionAndUpdatesOrdinaryTraversal() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        await fixture.model.play(track: fixture.second[1])
        fixture.model.seek(to: 4)
        let loadedBeforeMove = fixture.audio.loadedURLs
        let secondSectionID = try XCTUnwrap(fixture.second[0].section?.id)
        let firstSectionID = try XCTUnwrap(fixture.first[0].section?.id)
        XCTAssertFalse(fixture.model.canPlayNext)

        XCTAssertTrue(fixture.model.moveSections(from: IndexSet(integer: 1), to: 0))

        XCTAssertEqual(fixture.model.sections.map(\.id), [secondSectionID, firstSectionID])
        XCTAssertEqual(fixture.model.selectedTrackID, fixture.second[1].id)
        XCTAssertEqual(fixture.model.lastPlayedSectionID, secondSectionID)
        XCTAssertEqual(fixture.audio.state.currentTime, 4)
        XCTAssertTrue(fixture.audio.state.isPlaying)
        XCTAssertEqual(fixture.audio.loadedURLs, loadedBeforeMove, "Reordering must not reload or restart audio.")
        XCTAssertTrue(fixture.model.canPlayNext, "Ordinary next must follow the new playlist order.")
        await fixture.model.performPlaybackCommand(.next)
        XCTAssertEqual(fixture.model.selectedTrackID, fixture.first[0].id)
        await fixture.model.performPlaybackCommand(.previous)
        XCTAssertEqual(fixture.model.selectedTrackID, fixture.second[1].id)
    }

    func testPlaylistMovePreservesShuffleHistoryAndPauseState() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        await fixture.model.play(track: fixture.first[0])
        fixture.setMode(.shuffle)
        await fixture.model.performPlaybackCommand(.next)
        let secondPlayedID = try XCTUnwrap(fixture.model.selectedTrackID)
        fixture.model.seek(to: 3)
        await fixture.model.performPlaybackCommand(.pause)
        let loadedBeforeMove = fixture.audio.loadedURLs

        XCTAssertTrue(fixture.model.moveSections(from: IndexSet(integer: 0), to: 2))

        XCTAssertEqual(fixture.model.selectedTrackID, secondPlayedID)
        XCTAssertEqual(fixture.audio.state.currentTime, 3)
        XCTAssertFalse(fixture.audio.state.isPlaying)
        XCTAssertEqual(fixture.audio.loadedURLs, loadedBeforeMove)
        await fixture.model.performPlaybackCommand(.previous)
        XCTAssertEqual(fixture.model.selectedTrackID, fixture.first[0].id, "Reordering playlists must not reshuffle playback history.")
        await fixture.model.performPlaybackCommand(.next)
        XCTAssertEqual(fixture.model.selectedTrackID, secondPlayedID)
        await fixture.model.performPlaybackCommand(.next)
        let lastPlayedID = try XCTUnwrap(fixture.model.selectedTrackID)
        XCTAssertEqual(Set([fixture.first[0].id, secondPlayedID, lastPlayedID]), Set(fixture.first.map(\.id)))
        XCTAssertFalse(fixture.model.canPlayNext)
    }

    func testPlaylistMoveRejectsInvalidOffsetsAndFailedWriteWithoutChangingState() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        await fixture.model.play(track: fixture.first[1])
        fixture.model.seek(to: 2)
        let originalOrder = fixture.model.sections.map(\.id)
        let loads = fixture.audio.loadedURLs
        XCTAssertFalse(fixture.model.moveSections(from: IndexSet(integer: 99), to: 0))
        XCTAssertFalse(fixture.model.moveSections(from: IndexSet(integer: 0), to: -1))
        XCTAssertTrue(fixture.model.moveSections(from: [], to: 0))
        XCTAssertTrue(fixture.model.moveSections(from: IndexSet(integer: 0), to: 1))
        XCTAssertEqual(fixture.storage.sectionOrderWrites, 0, "No-op and invalid input must not write storage.")
        fixture.storage.rejectsSectionOrder = true
        XCTAssertFalse(fixture.model.moveSections(from: IndexSet(integer: 0), to: 2))
        XCTAssertEqual(fixture.model.sections.map(\.id), originalOrder)
        XCTAssertEqual(fixture.model.selectedTrackID, fixture.first[1].id)
        XCTAssertEqual(fixture.audio.state.currentTime, 2)
        XCTAssertTrue(fixture.audio.state.isPlaying)
        XCTAssertEqual(fixture.audio.loadedURLs, loads)
        XCTAssertNotNil(fixture.model.importError)
    }

    func testLegacyPreferencesMigrateWithDeterministicPriority() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let cases: [(String?, Bool, PlaybackMode)] = [
            ("one", true, .repeatOne), ("one", false, .repeatOne),
            ("playlist", true, .shuffle), ("playlist", false, .repeatPlaylist),
            ("off", true, .shuffle), ("off", false, .off),
            (nil, false, .off), ("invalid", false, .off)
        ]
        for (legacyRepeat, shuffle, expected) in cases {
            fixture.defaults.removeObject(forKey: "playbackMode")
            fixture.defaults.set(legacyRepeat, forKey: "playbackRepeatMode")
            fixture.defaults.set(shuffle, forKey: "playbackShuffleEnabled")
            let restored = fixture.makeModel()
            XCTAssertEqual(restored.playbackMode, expected)
            XCTAssertEqual(fixture.defaults.string(forKey: "playbackMode"), expected.rawValue)
        }
        fixture.defaults.set("invalid", forKey: "playbackMode")
        fixture.defaults.set("playlist", forKey: "playbackRepeatMode")
        fixture.defaults.set(false, forKey: "playbackShuffleEnabled")
        XCTAssertEqual(fixture.makeModel().playbackMode, .repeatPlaylist)

        fixture.defaults.set(PlaybackMode.off.rawValue, forKey: "playbackMode")
        fixture.defaults.set("one", forKey: "playbackRepeatMode")
        fixture.defaults.set(true, forKey: "playbackShuffleEnabled")
        XCTAssertEqual(fixture.makeModel().playbackMode, .off,
                       "An explicit current preference takes priority over retained legacy keys")
    }
}

@MainActor
private final class Fixture {
    let defaults: UserDefaults
    private let suiteName = "ATPlayer.PlaybackSessionTests.\(UUID().uuidString)"
    let storage: MemoryPlaylistStore
    let audio = AudioDouble()
    let media = MediaDouble()
    let activity = ActivityDouble()
    let nowPlaying = NowPlayingDouble()
    let first: [PlaylistTrack]
    let second: [PlaylistTrack]
    lazy var model = ATPlayerViewModel(
        storage: storage, audio: audio, activity: activity,
        nowPlaying: nowPlaying, mediaAccess: media, defaults: defaults
    )

    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        first = Self.tracks(prefix: "first", count: 3)
        second = Self.tracks(prefix: "second", count: 2)
        storage = MemoryPlaylistStore(sections: [
            Playlist(name: "First", order: 0, tracks: first),
            Playlist(name: "Second", order: 1, tracks: second)
        ])
    }

    func makeModel() -> ATPlayerViewModel {
        ATPlayerViewModel(
            storage: storage, audio: AudioDouble(), activity: ActivityDouble(),
            nowPlaying: NowPlayingDouble(), mediaAccess: MediaDouble(), defaults: defaults
        )
    }

    func setMode(_ mode: PlaybackMode) {
        for _ in PlaybackMode.allCases where model.playbackMode != mode {
            model.cyclePlaybackMode()
        }
        XCTAssertEqual(model.playbackMode, mode)
    }

    func cleanup() {
        media.releaseDownload()
        audio.onTrackFinished = nil
        audio.onLoad = nil
        activity.onEnd = nil
        audio.stop()
        defaults.removePersistentDomain(forName: suiteName)
    }

    private static func tracks(prefix: String, count: Int) -> [PlaylistTrack] {
        (0..<count).map { index in
            PlaylistTrack(
                title: "\(prefix)-\(index)", artist: "Fixture", filePath: "/fixture/\(prefix)-\(index).wav",
                bookmark: Data(), duration: 10, order: index
            )
        }
    }
}

@MainActor
private final class AudioDouble: AudioPlaying {
    let state = AudioPlaybackState()
    var onTrackFinished: (() -> Void)?
    var onLoad: ((URL) -> Void)?
    var loadedURLs: [URL] = []
    var invalidPaths: Set<String> = []
    var isStoppedExternally = false
    private(set) var resumeCalls = 0

    func loadAndPlay(url: URL) async throws {
        if invalidPaths.contains(url.path) { throw PlaybackError.invalidAudioFile }
        loadedURLs.append(url)
        state.duration = 10
        state.currentTime = 0
        state.isStarting = false
        state.isPlaying = true
        onLoad?(url)
    }

    func play() -> Task<Void, Error>? {
        resumeCalls += 1
        state.isPlaying = state.duration > 0
        state.isStarting = false
        return nil
    }

    func pauseByUser() { pause() }

    func reconcilePlaybackState() {
        guard isStoppedExternally else { return }
        isStoppedExternally = false
        pause()
    }

    func pause() {
        state.isPlaying = false
        state.isStarting = false
    }

    func stop() {
        pause()
        state.currentTime = 0
        state.duration = 0
    }

    func seek(to time: TimeInterval) {
        state.currentTime = min(state.duration, max(0, time))
        if state.duration > 0, state.currentTime == state.duration { finishTrack() }
    }

    func finishTrack() {
        state.currentTime = state.duration
        state.isPlaying = false
        onTrackFinished?()
    }
}

@MainActor
private final class MediaDouble: MediaResourceAccess {
    var resolvedPaths: [String] = []
    var unavailablePaths: Set<String> = []
    var delayedPath: String?
    var onDownloadStarted: (() -> Void)?
    private var downloadContinuation: CheckedContinuation<Void, Never>?

    func openImportResource(at url: URL) throws -> ImportMediaResource {
        ImportMediaResource(url: url, directoryURL: nil, scopedURL: nil)
    }

    func releaseAccess(to scopedURL: URL?) {}

    func makeBookmark(for url: URL, directoryURL: URL?) throws -> Data {
        Data(url.absoluteString.utf8)
    }

    func resolve(bookmark: Data, filePath: String) throws -> ResolvedMediaResource {
        resolvedPaths.append(filePath)
        return ResolvedMediaResource(url: URL(fileURLWithPath: filePath), scopedURL: nil, refreshedBookmark: nil)
    }

    func ensureDownloaded(_ url: URL, isCurrent: @escaping @MainActor () -> Bool) async throws -> Bool {
        if url.path == delayedPath {
            await withCheckedContinuation { continuation in
                downloadContinuation = continuation
                onDownloadStarted?()
            }
        }
        return !Task.isCancelled && isCurrent() && !unavailablePaths.contains(url.path)
    }

    func releaseDownload() {
        let continuation = downloadContinuation
        downloadContinuation = nil
        continuation?.resume()
    }

    func metadata(at url: URL) async throws -> MediaMetadata {
        MediaMetadata(title: url.deletingPathExtension().lastPathComponent, artist: "Fixture", duration: 10, artwork: nil)
    }

    func collectAudioFiles(in directoryURL: URL) async -> [URL] { [] }
}

@MainActor
private final class NowPlayingDouble: NowPlayingPresenting {
    var handleCommand: (@MainActor @Sendable (PlaybackCommand) -> Void)?
    private(set) var snapshot: PlaybackSnapshot?
    func update(_ snapshot: PlaybackSnapshot, force: Bool) { self.snapshot = snapshot }
    func clear() { snapshot = nil }
}

@MainActor
private final class ActivityDouble: ActivityPresenting {
    var onEnd: (() -> Void)?
    private(set) var snapshot: PlaybackSnapshot?
    private(set) var forcedUpdateCount = 0
    func endAllStaleActivities() { snapshot = nil }
    func synchronize(_ snapshot: PlaybackSnapshot, playbackStartDate: Date, allowStart: Bool, force: Bool) {
        self.snapshot = snapshot
        if force { forcedUpdateCount += 1 }
    }
    func retryWhenForegrounded() {}
    func endActivity() {
        snapshot = nil
        let callback = onEnd
        onEnd = nil
        callback?()
    }
}

@MainActor
private final class MemoryPlaylistStore: PlaylistStoring {
    private enum StoreError: Error { case invalidTrackOrder, invalidSectionOrder, rejectedWrite }
    var rejectsSectionOrder = false
    private(set) var sectionOrderWrites = 0
    private var sections: [Playlist]
    init(sections: [Playlist]) { self.sections = sections }
    func fetchSections() throws -> [Playlist] { sections.sorted { $0.order < $1.order } }
    func createSection(name: String) throws -> Playlist {
        let section = Playlist(name: name, order: sections.count)
        sections.append(section)
        return section
    }
    func removeSection(_ section: Playlist) throws {
        sections.removeAll { $0.id == section.id }
        for (index, item) in sections.enumerated() { item.order = index }
    }
    func renameSection(_ section: Playlist, to name: String) throws { section.name = name }
    func ensureDefaultSection() throws -> Playlist {
        if let first = sections.first { return first }
        return try createSection(name: "My Music")
    }
    func sortedTracks(in section: Playlist) -> [PlaylistTrack] { section.tracks.sorted { $0.order < $1.order } }
    func appendTrack(title: String, artist: String, url: URL, bookmark: Data, duration: Double,
                     artwork: Data?, to section: Playlist) throws -> PlaylistTrack {
        let track = PlaylistTrack(title: title, artist: artist, filePath: url.path, bookmark: bookmark,
                                  duration: duration, order: section.tracks.count, artwork: artwork)
        track.section = section
        section.tracks.append(track)
        return track
    }
    func setCorrupted(_ isCorrupted: Bool, for track: PlaylistTrack) throws { track.isCorrupted = isCorrupted }
    func updateBookmark(for track: PlaylistTrack, bookmark: Data, url: URL) throws {
        track.bookmark = bookmark
        track.filePath = url.path
    }
    func removeTrack(_ track: PlaylistTrack) throws {
        guard let section = track.section else { return }
        try removeTracks(withIDs: [track.id], from: section)
    }
    func removeTracks(withIDs trackIDs: Set<UUID>, from section: Playlist) throws {
        section.tracks.removeAll { trackIDs.contains($0.id) }
        for (index, track) in section.tracks.enumerated() { track.order = index }
    }
    func setSectionOrder(_ sectionIDs: [UUID]) throws {
        guard !rejectsSectionOrder else { throw StoreError.rejectedWrite }
        guard sectionIDs.count == sections.count, Set(sectionIDs) == Set(sections.map(\.id)) else {
            throw StoreError.invalidSectionOrder
        }
        sectionOrderWrites += 1
        for (index, id) in sectionIDs.enumerated() {
            sections.first { $0.id == id }?.order = index
        }
    }
    func setTrackOrder(_ trackIDs: [UUID], in section: Playlist) throws {
        guard trackIDs.count == section.tracks.count, Set(trackIDs) == Set(section.tracks.map(\.id)) else {
            throw StoreError.invalidTrackOrder
        }
        for (index, id) in trackIDs.enumerated() {
            section.tracks.first { $0.id == id }?.order = index
        }
    }
}
