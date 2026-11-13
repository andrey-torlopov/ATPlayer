import Combine
import Foundation
import LibraryDomain
import PlaybackDomain
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import PlayerFeature
@testable import PlayerInfrastructure

@MainActor
final class PlaylistImportTests: XCTestCase {
    private let importTimeout: TimeInterval = 10

    func testDirectSelectionRejectsEmptyCorruptAndUnsupportedFilesAndContinuesImport() async throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        let invalid = try fixture.makeInvalidFiles()
        let valid = try fixture.writeWAV(named: "valid.WAV")

        await importFiles(invalid + [valid], into: fixture.model)

        XCTAssertEqual(fixture.model.allTracks.map(\.filePath), [valid.path],
                       "A bad selection must neither enter the playlist nor prevent later valid files from importing.")
        XCTAssertEqual(try fixture.persistedTracks().map(\.filePath), [valid.path])
        XCTAssertEqual(fixture.model.allTracks.first?.duration ?? 0, 0.1, accuracy: 0.001)
        XCTAssertNotNil(fixture.model.importError, "Rejected direct selections should report the import failure.")
    }

    func testRecursiveImportPersistsOnlyDecodableAudioFromMixedTree() async throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        _ = try fixture.makeInvalidFiles()
        let nested = fixture.root.appendingPathComponent("Album/Disc", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let first = try fixture.writeWAV(named: "root.wav")
        let second = try fixture.writeWAV(named: "Album/Disc/nested.WAV")
        try Data().write(to: nested.appendingPathComponent("empty.mp3"))
        try Data("not FLAC audio".utf8).write(to: nested.appendingPathComponent("broken.flac"))

        await importFiles([fixture.root], into: fixture.model)

        let expected = Set([first.path, second.path])
        XCTAssertEqual(Set(fixture.model.allTracks.map(\.filePath)), expected)
        let persisted = try fixture.persistedTracks()
        XCTAssertEqual(Set(persisted.map(\.filePath)), expected,
                       "Inspect a new SwiftData context so a UI-only filter cannot mask saved bad tracks.")
        XCTAssertTrue(persisted.allSatisfy { $0.duration > 0 && !$0.isCorrupted })
    }

    func testEntirelyInvalidSelectionLeavesPlaylistAndStoredTracksEmpty() async throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }

        await importFiles(try fixture.makeInvalidFiles(), into: fixture.model)

        XCTAssertTrue(fixture.model.allTracks.isEmpty)
        XCTAssertTrue(try fixture.persistedTracks().isEmpty)
        XCTAssertFalse(fixture.model.isImporting)
        XCTAssertNotNil(fixture.model.importError)
    }

    func testImporterOffersSpecificPlayableTypesAndFolders() throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        let types = fixture.model.supportedTypes

        XCTAssertFalse(types.contains(.audio), "The broad audio type also offers unsupported formats.")
        XCTAssertTrue(types.contains(.folder))
        for ext in ["mp3", "flac", "wav", "m4a", "aac", "aiff", "caf"] {
            let type = try XCTUnwrap(UTType(filenameExtension: ext))
            XCTAssertTrue(types.contains(type), "Missing supported file type: \(ext)")
        }
    }

    func testReportedMP3ImportsAndPersistsWithoutBeingMarkedCorrupt() async throws {
        let url = try ReportedMP3Fixture.url()
        XCTAssertEqual(url.lastPathComponent, ReportedMP3Fixture.fileName)
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }

        await importFiles([url], into: fixture.model)

        XCTAssertNil(fixture.model.importError)
        XCTAssertEqual(fixture.model.allTracks.map(\.filePath), [url.path])
        let persisted = try fixture.persistedTracks()
        XCTAssertEqual(persisted.map(\.filePath), [url.path])
        let track = try XCTUnwrap(persisted.first)
        XCTAssertFalse(track.isCorrupted)
        XCTAssertGreaterThan(track.duration, 300)
        XCTAssertFalse(track.bookmark.isEmpty)
        try assertBookmarkResolves(track, to: url)
    }

    func testReportedMP3OriginalNameSurvivesRecursiveImportAndDirectoryBookmark() async throws {
        let original = try ReportedMP3Fixture.url()
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        let album = fixture.root.appendingPathComponent("Album", isDirectory: true)
        try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
        let url = album.appendingPathComponent(ReportedMP3Fixture.fileName)
        try FileManager.default.copyItem(at: original, to: url)

        await importFiles([fixture.root], into: fixture.model)

        XCTAssertNil(fixture.model.importError)
        let tracks = try fixture.persistedTracks()
        XCTAssertEqual(tracks.map(\.filePath), [url.path])
        let track = try XCTUnwrap(tracks.first)
        XCTAssertFalse(track.isCorrupted)
        try assertBookmarkResolves(track, to: url)
    }

    private func assertBookmarkResolves(_ track: PlaylistTrack, to original: URL) throws {
        let access = PlaylistMediaAccess()
        let resource = try access.resolve(bookmark: track.bookmark, filePath: track.filePath)
        defer { access.releaseAccess(to: resource.scopedURL) }
        XCTAssertEqual(resource.url.lastPathComponent, ReportedMP3Fixture.fileName)
        XCTAssertEqual(resource.url.resolvingSymlinksInPath(), original.resolvingSymlinksInPath())
        XCTAssertGreaterThan(try AudioFileValidator.validate(resource.url), 300)
    }

    private func importFiles(_ urls: [URL], into model: ATPlayerViewModel) async {
        let finished = expectation(description: "Playlist import completed")
        let observation = model.$isImporting
            .dropFirst()
            .filter { !$0 }
            .prefix(1)
            .sink { _ in finished.fulfill() }
        defer { observation.cancel() }
        model.importFiles(.success(urls))
        await fulfillment(of: [finished], timeout: importTimeout)
    }
}

@MainActor
private final class ImportFixture {
    let root: URL
    let container: ModelContainer
    let model: ATPlayerViewModel
    private let defaults: UserDefaults
    private let suiteName = "ATPlayer.PlaylistImportTests.\(UUID().uuidString)"

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        container = try PlaylistStorageService.createContainer(inMemory: true)
        model = ATPlayerViewModel(
            storage: PlaylistStorageService(context: container.mainContext),
            audio: ImportAudioDouble(), activity: ImportActivityDouble(),
            nowPlaying: ImportNowPlayingDouble(), mediaAccess: PlaylistMediaAccess(), defaults: defaults
        )
    }

    func cleanup() {
        model.shutdown()
        defaults.removePersistentDomain(forName: suiteName)
        do { try FileManager.default.removeItem(at: root) }
        catch { XCTFail("Could not remove import fixtures: \(error)") }
    }

    func persistedTracks() throws -> [PlaylistTrack] {
        let storage = PlaylistStorageService(context: ModelContext(container))
        return try storage.fetchSections().flatMap { storage.sortedTracks(in: $0) }
    }

    func makeInvalidFiles() throws -> [URL] {
        let contents: [(String, Data)] = [
            ("empty.mp3", Data()),
            ("empty.wav", Data()),
            ("broken.mp3", Data("This is text, not MPEG audio.".utf8)),
            ("broken.flac", Data("fLaC but no valid stream follows".utf8)),
            ("broken.wav", Data(repeating: 0xFF, count: 128)),
            ("header-only.wav", Self.wavData(frames: 0)),
            ("notes.txt", Data("Not music".utf8)),
            ("audio-with-unsupported-extension.txt", Self.wavData(frames: 800))
        ]
        return try contents.map { name, data in
            let url = root.appendingPathComponent(name)
            try data.write(to: url)
            return url
        }
    }

    func writeWAV(named name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Self.wavData(frames: 800).write(to: url)
        return url
    }

    /// PCM, mono, 16-bit, 8 kHz. Zero samples are valid silence, not an empty file.
    private static func wavData(frames: UInt32) -> Data {
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func uint16(_ value: UInt16) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        func uint32(_ value: UInt32) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        let audioBytes = frames * 2
        text("RIFF")
        uint32(36 + audioBytes)
        text("WAVEfmt ")
        uint32(16)
        uint16(1)
        uint16(1)
        uint32(8_000)
        uint32(16_000)
        uint16(2)
        uint16(16)
        text("data")
        uint32(audioBytes)
        data.append(Data(repeating: 0, count: Int(audioBytes)))
        return data
    }
}

@MainActor
private final class ImportAudioDouble: AudioPlaying {
    let state = AudioPlaybackState()
    var onTrackFinished: (() -> Void)?
    func loadAndPlay(url: URL) async throws {
        XCTFail("Import must not start playback.")
        throw PlaybackError.invalidAudioFile
    }
    func play() -> Task<Void, Error>? { nil }
    func pauseByUser() { state.isPlaying = false }
    func pause() { state.isPlaying = false }
    func stop() { state.isPlaying = false }
    func seek(to time: TimeInterval) { state.currentTime = time }
}

@MainActor
private final class ImportNowPlayingDouble: NowPlayingPresenting {
    var handleCommand: (@MainActor @Sendable (PlaybackCommand) -> Void)?
    func update(_ snapshot: PlaybackSnapshot, force: Bool) {}
    func clear() {}
}

@MainActor
private final class ImportActivityDouble: ActivityPresenting {
    func endAllStaleActivities() {}
    func synchronize(_ snapshot: PlaybackSnapshot, playbackStartDate: Date, allowStart: Bool, force: Bool) {}
    func retryWhenForegrounded() {}
    func endActivity() {}
}
