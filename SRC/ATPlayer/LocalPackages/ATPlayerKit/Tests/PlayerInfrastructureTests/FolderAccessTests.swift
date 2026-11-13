import Foundation
import FolderDomain
import PlaybackDomain
import XCTest
@testable import PlayerInfrastructure

final class FolderAccessTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let cache: URL
        let service: FolderAccessService
    }

    private func fixture(budget: Int64 = 1024 * 1024) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let root = directory.appendingPathComponent("Music", isDirectory: true)
        let cache = directory.appendingPathComponent("Cache", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return Fixture(root: root, cache: cache, service: FolderAccessService(cacheDirectory: cache, maximumCacheBytes: budget))
    }

    /// A complete mono PCM WAV, with no external fixture or encoder dependency.
    private func wavData(frames: UInt32 = 64, sample: UInt16 = 1) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        append(UInt32(36) + frames * 2)
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(8_000))
        append(UInt32(16_000))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: "data".utf8)
        append(frames * 2)
        for _ in 0..<frames { append(sample) }
        return data
    }

    func testListingIsOneLevelNaturallySortedAndRejectsSymlinks() async throws {
        let fixture = try fixture()
        let nested = fixture.root.appendingPathComponent("Album 2", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fixture.root.appendingPathComponent("Album 10", isDirectory: true), withIntermediateDirectories: true)
        try wavData().write(to: nested.appendingPathComponent("Nested.wav"))
        try wavData().write(to: fixture.root.appendingPathComponent("Album 10/Nested.wav"))
        for name in ["Track 10.wav", "Track 2.wav", ".hidden.wav", "notes.txt"] {
            try wavData().write(to: fixture.root.appendingPathComponent(name))
        }
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("Link", isDirectory: true), withDestinationURL: nested)
        let source = try await fixture.service.makeSource(at: fixture.root)
        let listing = try await fixture.service.list(source: source, relativePath: "")
        XCTAssertEqual(listing.entries.map(\.name), ["Album 2", "Album 10", "Track 2.wav", "Track 10.wav"])
        XCTAssertEqual(listing.entries.map(\.kind), [.directory, .directory, .audio, .audio])
        let repeated = try await fixture.service.list(source: source, relativePath: "")
        XCTAssertEqual(listing.entries.map(\.id), repeated.entries.map(\.id), "Rescanning must preserve row and playback identity.")
        let child = try await fixture.service.list(source: source, relativePath: "Album 2")
        XCTAssertEqual(child.entries.map(\.relativePath), ["Album 2/Nested.wav"])
        for path in ["..", "Album 2/../Album 10", "/tmp", "Link", "Album 2//child"] {
            do {
                _ = try await fixture.service.list(source: source, relativePath: path)
                XCTFail("Traversal or link path must fail: \(path)")
            } catch FolderAccessError.invalidPath { }
        }
    }

    func testDirectoriesWithoutAudioAreHiddenButAncestorsOfMusicRemainVisible() async throws {
        let fixture = try fixture()
        for path in ["Empty", "Documents/Subfolder", "Hidden/.Album", "Links", "Broken/Disc", "Deep/Album/Disc"] {
            try FileManager.default.createDirectory(at: fixture.root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        try Data([1]).write(to: fixture.root.appendingPathComponent("Documents/Subfolder/notes.txt"))
        try Data([1]).write(to: fixture.root.appendingPathComponent("Hidden/.song.mp3"))
        try Data([1]).write(to: fixture.root.appendingPathComponent("Hidden/.Album/song.flac"))
        try Data().write(to: fixture.root.appendingPathComponent("Broken/Disc/empty.wav"))
        try Data("Not audio".utf8).write(to: fixture.root.appendingPathComponent("Broken/corrupt.mp3"))
        let deepAudio = fixture.root.appendingPathComponent("Deep/Album/Disc/Song.WAV")
        try wavData().write(to: deepAudio)
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("Links/song.mp3"), withDestinationURL: deepAudio)
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("Links/cycle"), withDestinationURL: fixture.root)
        let source = try await fixture.service.makeSource(at: fixture.root)
        let listing = try await fixture.service.list(source: source, relativePath: "")
        XCTAssertEqual(listing.entries.map(\.name), ["Deep"], "Only subtrees leading to visible supported music should remain.")
        XCTAssertTrue(listing.entries.allSatisfy { $0.kind == .directory }, "Discovery must not flatten descendant tracks into this level.")
        let child = try await fixture.service.list(source: source, relativePath: "Deep")
        XCTAssertEqual(child.entries.map(\.relativePath), ["Deep/Album"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.cache.path), "Checking visibility must not create a playback cache.")

        try FileManager.default.removeItem(at: deepAudio)
        let emptied = try await fixture.service.list(source: source, relativePath: "")
        XCTAssertTrue(emptied.entries.isEmpty, "Refresh must hide a subtree after its last audio file disappears.")
        try wavData().write(to: fixture.root.appendingPathComponent("Empty/New.wav"))
        let updated = try await fixture.service.list(source: source, relativePath: "")
        XCTAssertEqual(updated.entries.map(\.name), ["Empty"], "An earlier negative result must not hide newly added music.")
    }

    func testSupportedExtensionsDoNotAdmitEmptyOrCorruptContents() async throws {
        let fixture = try fixture()
        for ext in SupportedAudioFormats.fileExtensions {
            let directory = fixture.root.appendingPathComponent(ext, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: directory.appendingPathComponent("Empty." + ext.uppercased()))
            try Data("This is not audio".utf8).write(to: directory.appendingPathComponent("Corrupt." + ext.uppercased()))
        }
        let source = try await fixture.service.makeSource(at: fixture.root)
        let listing = try await fixture.service.list(source: source, relativePath: "")
        XCTAssertTrue(listing.entries.isEmpty, "An accepted extension is not proof of playable audio.")
    }

    func testListingSkipsInvalidFilesAndKeepsValidUppercaseAudio() async throws {
        let fixture = try fixture()
        try wavData().write(to: fixture.root.appendingPathComponent("Valid.WAV"))
        try wavData().write(to: fixture.root.appendingPathComponent("Unsupported.txt"))
        try wavData(frames: 0).write(to: fixture.root.appendingPathComponent("HeaderOnly.wav"))
        try Data().write(to: fixture.root.appendingPathComponent("Empty.wav"))
        for ext in ["mp3", "flac", "wav"] {
            try Data("Corrupt audio payload".utf8).write(to: fixture.root.appendingPathComponent("Broken." + ext))
        }
        let source = try await fixture.service.makeSource(at: fixture.root)
        let listing = try await fixture.service.list(source: source, relativePath: "")
        XCTAssertEqual(listing.entries.map(\.name), ["Valid.WAV"])
        XCTAssertEqual(listing.entries.map(\.kind), [.audio])
    }

    func testPrepareRejectsFilesCorruptedAfterListingAndCleansCache() async throws {
        for replacement in [Data(), Data("Corrupt after discovery".utf8), wavData(frames: 0)] {
            let fixture = try fixture()
            let file = fixture.root.appendingPathComponent("Track.wav")
            try wavData().write(to: file)
            let source = try await fixture.service.makeSource(at: fixture.root)
            let listing = try await fixture.service.list(source: source, relativePath: "")
            let entry = try XCTUnwrap(listing.entries.first)
            try replacement.write(to: file)
            do {
                _ = try await fixture.service.prepare(source: source, entry: entry, priority: .playback)
                XCTFail("A file that became invalid after discovery must never receive a playback lease.")
            } catch FolderAccessError.unsupportedFile { }
            let cached = try FileManager.default.contentsOfDirectory(at: fixture.cache, includingPropertiesForKeys: nil)
            XCTAssertTrue(cached.isEmpty, "Rejected audio must leave no complete or partial cache file.")
            XCTAssertEqual(try Data(contentsOf: file), replacement, "Validation must never change the original.")
        }
    }

    func testUnreadableSubtreeDoesNotHideAccessibleSiblings() async throws {
        let fixture = try fixture()
        let locked = fixture.root.appendingPathComponent("Unavailable", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try wavData().write(to: fixture.root.appendingPathComponent("Song.wav"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer {
            do { try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
            catch { XCTFail("Could not restore fixture permissions") }
        }
        let source = try await fixture.service.makeSource(at: fixture.root)
        let listing = try await fixture.service.list(source: source, relativePath: "")
        XCTAssertEqual(listing.entries.map(\.name), ["Unavailable", "Song.wav"], "Unknown contents must not be treated as empty or break readable siblings.")
    }

    func testCacheReuseInvalidationAndPinning() async throws {
        let original = wavData(frames: 64)
        let updated = wavData(frames: 96, sample: 2)
        let fixture = try fixture(budget: Int64(updated.count))
        let file = fixture.root.appendingPathComponent("Track.wav")
        try original.write(to: file)
        let source = try await fixture.service.makeSource(at: fixture.root)
        let firstList = try await fixture.service.list(source: source, relativePath: "")
        let entry = try XCTUnwrap(firstList.entries.first)
        let first = try await fixture.service.prepare(source: source, entry: entry, priority: .playback)
        XCTAssertEqual(try Data(contentsOf: first.url), original)
        XCTAssertNotEqual(first.url, file, "The engine must receive a cache URL, never the external URL.")
        let second = try await fixture.service.prepare(source: source, entry: entry, priority: .playback)
        XCTAssertEqual(first.url, second.url, "Repeated preparation must reuse the completed copy.")
        XCTAssertNotEqual(first.id, second.id, "Independent consumers need separate leases.")
        await fixture.service.release(second)

        try updated.write(to: file)
        let refreshed = try await fixture.service.list(source: source, relativePath: "")
        let changed = try XCTUnwrap(refreshed.entries.first)
        let third = try await fixture.service.prepare(source: source, entry: changed, priority: .playback)
        XCTAssertNotEqual(first.url, third.url, "Changed metadata must invalidate the previous cache version.")
        XCTAssertEqual(try Data(contentsOf: third.url), updated)
        XCTAssertEqual(try Data(contentsOf: first.url), original, "A playing old version must remain untouched during handoff.")
        await fixture.service.release(first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path), "Releasing the old pin must reclaim over-budget data.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: third.url.path))
        await fixture.service.release(third)
    }

    func testPrefetchBudgetAndLargeSelectedFile() async throws {
        let fixture = try fixture(budget: 4)
        let file = fixture.root.appendingPathComponent("Long recording.wav")
        let audio = wavData()
        try audio.write(to: file)
        let source = try await fixture.service.makeSource(at: fixture.root)
        let listing = try await fixture.service.list(source: source, relativePath: "")
        let entry = try XCTUnwrap(listing.entries.first)
        do {
            _ = try await fixture.service.prepare(source: source, entry: entry, priority: .prefetch)
            XCTFail("Speculative downloads must respect the budget.")
        } catch FolderAccessError.cacheCapacity { }
        let lease = try await fixture.service.prepare(source: source, entry: entry, priority: .playback)
        XCTAssertEqual(try Data(contentsOf: lease.url), audio, "Explicit selection must allow one long recording beyond the soft budget.")
        await fixture.service.release(lease)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lease.url.path), "Unpinned oversized files must be removed.")
    }

    func testForgetDefersPinnedDeletionAndNeverDeletesOriginal() async throws {
        let fixture = try fixture()
        let file = fixture.root.appendingPathComponent("Track.wav")
        let audio = wavData()
        try audio.write(to: file)
        let source = try await fixture.service.makeSource(at: fixture.root)
        let listing = try await fixture.service.list(source: source, relativePath: "")
        let entry = try XCTUnwrap(listing.entries.first)
        let lease = try await fixture.service.prepare(source: source, entry: entry, priority: .playback)
        await fixture.service.forget(sourceID: source.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lease.url.path), "An outstanding audio reader retains its copy until release.")
        await fixture.service.release(lease)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lease.url.path))
        XCTAssertEqual(try Data(contentsOf: file), audio, "Forgetting a root may only remove app-owned cache files.")
    }

    func testCancelledRequestReturnsBeforeBlockedWorkerAndDiscardsLateResult() async throws {
        let fixture = try fixture()
        let lateFile = fixture.root.appendingPathComponent("late.tmp")
        let started = expectation(description: "worker entered")
        let finished = expectation(description: "late worker cleaned up")
        let gate = DispatchSemaphore(value: 0)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let request = FolderIORequest<URL>(discard: { url in
            do { try FileManager.default.removeItem(at: url) }
            catch { XCTFail("Late result cleanup failed") }
        }, finished: { finished.fulfill() })
        let task = Task {
            try await request.run(on: queue, timeout: 60) { _ in
                started.fulfill()
                guard gate.wait(timeout: .now() + 5) == .success else { throw FolderAccessError.timedOut }
                try Data([8]).write(to: lateFile)
                return lateFile
            }
        }
        await fulfillment(of: [started], timeout: 3)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled caller must not receive a file.")
        } catch is CancellationError { }
        gate.signal()
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lateFile.path), "A late accessor result must never leak a cache file.")
    }

    func testTimeoutDoesNotPublishLateSuccess() async throws {
        let started = expectation(description: "worker entered")
        let finished = expectation(description: "worker finished")
        let discarded = expectation(description: "result discarded")
        let gate = DispatchSemaphore(value: 0)
        let queue = OperationQueue()
        let request = FolderIORequest<Int>(discard: { _ in discarded.fulfill() }, finished: { finished.fulfill() })
        let task = Task {
            try await request.run(on: queue, timeout: 0.05) { _ in
                started.fulfill()
                guard gate.wait(timeout: .now() + 5) == .success else { throw FolderAccessError.timedOut }
                return 1
            }
        }
        await fulfillment(of: [started], timeout: 3)
        do {
            _ = try await task.value
            XCTFail("The caller must receive a timeout before the blocked accessor returns.")
        } catch FolderAccessError.timedOut { }
        gate.signal()
        await fulfillment(of: [finished, discarded], timeout: 3)
    }
}
