import Foundation
import FolderDomain
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

    func testListingIsOneLevelNaturallySortedAndRejectsSymlinks() async throws {
        let fixture = try fixture()
        let nested = fixture.root.appendingPathComponent("Album 2", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fixture.root.appendingPathComponent("Album 10", isDirectory: true), withIntermediateDirectories: true)
        try Data([1]).write(to: nested.appendingPathComponent("Nested.mp3"))
        for name in ["Track 10.mp3", "Track 2.mp3", ".hidden.mp3", "notes.txt"] {
            try Data([2]).write(to: fixture.root.appendingPathComponent(name))
        }
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("Link", isDirectory: true), withDestinationURL: nested)
        let source = try await fixture.service.makeSource(at: fixture.root)
        let listing = try await fixture.service.list(source: source, relativePath: "")
        XCTAssertEqual(listing.entries.map(\.name), ["Album 2", "Album 10", "Track 2.mp3", "Track 10.mp3"])
        XCTAssertEqual(listing.entries.map(\.kind), [.directory, .directory, .audio, .audio])
        let repeated = try await fixture.service.list(source: source, relativePath: "")
        XCTAssertEqual(listing.entries.map(\.id), repeated.entries.map(\.id), "Rescanning must preserve row and playback identity.")
        let child = try await fixture.service.list(source: source, relativePath: "Album 2")
        XCTAssertEqual(child.entries.map(\.relativePath), ["Album 2/Nested.mp3"])
        for path in ["..", "Album 2/../Album 10", "/tmp", "Link", "Album 2//child"] {
            do {
                _ = try await fixture.service.list(source: source, relativePath: path)
                XCTFail("Traversal or link path must fail: \(path)")
            } catch FolderAccessError.invalidPath { }
        }
    }

    func testCacheReuseInvalidationAndPinning() async throws {
        let fixture = try fixture(budget: 12)
        let file = fixture.root.appendingPathComponent("Track.mp3")
        let original = Data(repeating: 1, count: 8)
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

        let updated = Data(repeating: 2, count: 9)
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
        try Data(repeating: 7, count: 20).write(to: file)
        let source = try await fixture.service.makeSource(at: fixture.root)
        let listing = try await fixture.service.list(source: source, relativePath: "")
        let entry = try XCTUnwrap(listing.entries.first)
        do {
            _ = try await fixture.service.prepare(source: source, entry: entry, priority: .prefetch)
            XCTFail("Speculative downloads must respect the budget.")
        } catch FolderAccessError.cacheCapacity { }
        let lease = try await fixture.service.prepare(source: source, entry: entry, priority: .playback)
        XCTAssertEqual(try Data(contentsOf: lease.url).count, 20, "Explicit selection must allow one long recording beyond the soft budget.")
        await fixture.service.release(lease)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lease.url.path), "Unpinned oversized files must be removed.")
    }

    func testForgetDefersPinnedDeletionAndNeverDeletesOriginal() async throws {
        let fixture = try fixture()
        let file = fixture.root.appendingPathComponent("Track.mp3")
        try Data([1, 2, 3]).write(to: file)
        let source = try await fixture.service.makeSource(at: fixture.root)
        let listing = try await fixture.service.list(source: source, relativePath: "")
        let entry = try XCTUnwrap(listing.entries.first)
        let lease = try await fixture.service.prepare(source: source, entry: entry, priority: .playback)
        await fixture.service.forget(sourceID: source.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lease.url.path), "An outstanding audio reader retains its copy until release.")
        await fixture.service.release(lease)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lease.url.path))
        XCTAssertEqual(try Data(contentsOf: file), Data([1, 2, 3]), "Forgetting a root may only remove app-owned cache files.")
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
