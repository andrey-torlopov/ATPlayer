import FolderDomain
import Foundation
import XCTest
@testable import PlayerInfrastructure

final class FolderSourceStoreTests: XCTestCase {
    func testRootsPersistWithoutDirectoryStateAndRemovalDoesNotResurrect() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("roots.json")
        let store = FolderSourceStore(url: file)
        let a = FolderSource(name: "Music", bookmark: Data([1, 2]))
        let b = FolderSource(name: "Music", bookmark: Data([3, 4]))
        _ = try await store.upsert(a)
        _ = try await store.upsert(b)
        let reopened = FolderSourceStore(url: file)
        let saved = try await reopened.load()
        XCTAssertEqual(saved.map(\.id), [a.id, b.id])
        XCTAssertEqual(saved.map(\.order), [0, 1])
        XCTAssertEqual(saved.map(\.bookmark), [a.bookmark, b.bookmark])

        let data = try Data(contentsOf: file)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["version", "sources"])
        let roots = try XCTUnwrap(object["sources"] as? [[String: Any]])
        XCTAssertEqual(Set(try XCTUnwrap(roots.first).keys), ["id", "name", "bookmark", "order"], "Directory entries, cache paths and navigation state must never be persisted.")

        _ = try await store.remove(id: a.id)
        var refreshed = a
        refreshed.bookmark = Data([9])
        let afterLateRefresh = try await store.updateExisting(refreshed)
        XCTAssertEqual(afterLateRefresh.map(\.id), [b.id], "A late bookmark refresh must never recreate a removed root.")
        XCTAssertEqual(afterLateRefresh.first?.order, 0)
    }

    func testBookmarkRefreshPreservesOrderAndOtherRoots() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let store = FolderSourceStore(url: directory.appendingPathComponent("roots.json"))
        let a = FolderSource(name: "A", bookmark: Data([1]))
        let b = FolderSource(name: "B", bookmark: Data([2]))
        _ = try await store.upsert(a)
        _ = try await store.upsert(b)
        var refreshed = b
        refreshed.order = 100
        refreshed.bookmark = Data([3])
        let result = try await store.updateExisting(refreshed)
        XCTAssertEqual(result.map(\.id), [a.id, b.id])
        XCTAssertEqual(result.map(\.order), [0, 1])
        XCTAssertEqual(result.last?.bookmark, Data([3]))
    }

    func testUnreadableDocumentIsNotOverwritten() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("roots.json")
        let original = Data("invalid document".utf8)
        try original.write(to: file)
        let store = FolderSourceStore(url: file)
        do {
            _ = try await store.upsert(FolderSource(name: "New", bookmark: Data()))
            XCTFail("An unreadable saved file must not be silently replaced.")
        } catch let error as FolderSourceStoreError {
            if case .unreadable = error {} else { XCTFail("Unexpected store failure") }
        }
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testFailedWriteLeavesExistingSourceFileUntouched() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let blocker = directory.appendingPathComponent("not-a-directory")
        let original = Data([1, 4, 9])
        try original.write(to: blocker)
        let store = FolderSourceStore(url: blocker.appendingPathComponent("roots.json"))
        do {
            _ = try await store.upsert(FolderSource(name: "New", bookmark: Data()))
            XCTFail("Saving below a regular file must fail.")
        } catch let error as FolderSourceStoreError {
            if case .writeFailed = error {} else { XCTFail("Unexpected store failure") }
        }
        XCTAssertEqual(try Data(contentsOf: blocker), original)
    }
}
