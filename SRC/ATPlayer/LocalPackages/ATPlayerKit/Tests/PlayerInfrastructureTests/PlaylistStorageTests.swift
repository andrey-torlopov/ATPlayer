import Foundation
import LibraryDomain
import SwiftData
import XCTest
@testable import PlayerInfrastructure

final class PlaylistStorageTests: XCTestCase {
    @MainActor
    func testStableDomainIdentityAndMetadataUpdates() throws {
        let container = try PlaylistStorageService.createContainer(inMemory: true)
        let storage = PlaylistStorageService(context: container.mainContext)
        let playlist = try storage.ensureDefaultSection()
        let track = try append("Track", to: playlist, using: storage)

        try storage.renameSection(playlist, to: "Renamed")
        try storage.updateBookmark(for: track, bookmark: Data([3, 4]), url: URL(fileURLWithPath: "/Music/moved.m4a"))
        try storage.setCorrupted(true, for: track)
        let reloaded = try XCTUnwrap(storage.fetchSections().first)

        XCTAssertTrue(reloaded === playlist, "Reloading must retain the object held by playlist editors.")
        XCTAssertTrue(reloaded.tracks.first === track, "Metadata refresh must preserve selected track identity.")
        XCTAssertEqual(playlist.name, "Renamed")
        XCTAssertEqual(track.bookmark, Data([3, 4]))
        XCTAssertEqual(track.filePath, "/Music/moved.m4a")
        XCTAssertTrue(track.isCorrupted)
        XCTAssertTrue(track.section === playlist)
    }

    @MainActor
    func testOrderValidationAndScopedDeletion() throws {
        let container = try PlaylistStorageService.createContainer(inMemory: true)
        let storage = PlaylistStorageService(context: container.mainContext)
        let a = try storage.createSection(name: "Same name")
        let b = try storage.createSection(name: "Same name")
        let first = try append("First", to: a, using: storage)
        let second = try append("Second", to: a, using: storage)
        let third = try append("Other playlist", to: b, using: storage)

        XCTAssertThrowsError(try storage.setTrackOrder([first.id, first.id], in: a))
        XCTAssertEqual(storage.sortedTracks(in: a).map(\.id), [first.id, second.id])
        try storage.setTrackOrder([second.id, first.id], in: a)
        XCTAssertEqual(storage.sortedTracks(in: a).map(\.id), [second.id, first.id])

        try storage.removeTracks(withIDs: [second.id, third.id], from: a)
        XCTAssertEqual(storage.sortedTracks(in: a).map(\.id), [first.id])
        XCTAssertEqual(first.order, 0)
        XCTAssertEqual(storage.sortedTracks(in: b).map(\.id), [third.id], "IDs from another playlist must not be deleted.")

        try storage.removeSection(a)
        let remaining = try storage.fetchSections()
        XCTAssertEqual(remaining.map(\.id), [b.id])
        XCTAssertEqual(b.order, 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TrackItem>()), 1, "Playlist deletion must cascade only to its tracks.")
    }

    @MainActor
    func testDiskRoundTripPreservesBookmarksAndOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("library.store")
        let ids = try populateStore(at: storeURL)

        let reopened = try PlaylistStorageService.createContainer(storeURL: storeURL)
        let storage = PlaylistStorageService(context: reopened.mainContext)
        let playlist = try XCTUnwrap(storage.fetchSections().first)
        let tracks = storage.sortedTracks(in: playlist)

        XCTAssertEqual(playlist.id, ids.playlist)
        XCTAssertEqual(tracks.map(\.id), [ids.second, ids.first])
        XCTAssertEqual(tracks.map(\.bookmark), [Data([1, 2]), Data([1, 2])])
        XCTAssertEqual(tracks.first?.artwork, Data([8, 9]))
        XCTAssertEqual(tracks.first?.duration, 125)
        XCTAssertEqual(tracks.first?.artist, "Artist")
    }

    @MainActor
    func testPlaylistOrderValidatesCompleteIDsAndPreservesTracks() throws {
        let container = try PlaylistStorageService.createContainer(inMemory: true)
        let storage = PlaylistStorageService(context: container.mainContext)
        let first = try storage.createSection(name: "Same name")
        let second = try storage.createSection(name: "Same name")
        let firstTrack = try append("First", to: first, using: storage)
        let secondTrack = try append("Second", to: second, using: storage)
        let original = [first.id, second.id]

        for invalidIDs in [[first.id], [first.id, first.id], [first.id, UUID()], original + [UUID()]] {
            XCTAssertThrowsError(try storage.setSectionOrder(invalidIDs))
            XCTAssertEqual(try storage.fetchSections().map(\.id), original)
            XCTAssertEqual([first.order, second.order], [0, 1], "Rejected input must not partially change retained snapshots.")
        }
        try storage.setSectionOrder([second.id, first.id])
        let reordered = try storage.fetchSections()
        XCTAssertEqual(reordered.map(\.id), [second.id, first.id])
        XCTAssertEqual(reordered.map(\.order), [0, 1])
        XCTAssertTrue(reordered[0] === second)
        XCTAssertTrue(reordered[1] === first)
        XCTAssertTrue(first.tracks.first === firstTrack)
        XCTAssertTrue(second.tracks.first === secondTrack)
        XCTAssertEqual(firstTrack.order, 0)
        XCTAssertEqual(secondTrack.order, 0)

        let added = try storage.createSection(name: "Third")
        XCTAssertThrowsError(try storage.setSectionOrder(original), "A stale editor cannot silently drop a newly added playlist.")
        XCTAssertEqual(try storage.fetchSections().map(\.id), [second.id, first.id, added.id])
    }

    @MainActor
    func testPlaylistOrderSurvivesDiskReopenWithDuplicateNames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("playlist-order.store")
        let expected = try populateReorderedPlaylists(at: storeURL)

        let container = try PlaylistStorageService.createContainer(storeURL: storeURL)
        let storage = PlaylistStorageService(context: container.mainContext)
        let sections = try storage.fetchSections()
        XCTAssertEqual(sections.map(\.id), expected.sections)
        XCTAssertEqual(sections.map(\.order), [0, 1, 2])
        XCTAssertEqual(sections.map(\.name), ["Same name", "Same name", "Same name"])
        XCTAssertEqual(sections.flatMap { storage.sortedTracks(in: $0).map(\.id) }, expected.tracks)
    }

    @MainActor
    private func populateReorderedPlaylists(at url: URL) throws -> (sections: [UUID], tracks: [UUID]) {
        let container = try PlaylistStorageService.createContainer(storeURL: url)
        let storage = PlaylistStorageService(context: container.mainContext)
        let first = try storage.createSection(name: "Same name")
        let second = try storage.createSection(name: "Same name")
        let third = try storage.createSection(name: "Same name")
        let firstTrack = try append("First", to: first, using: storage)
        let secondTrack = try append("Second", to: second, using: storage)
        let thirdTrack = try append("Third", to: third, using: storage)
        try storage.setSectionOrder([third.id, first.id, second.id])
        return ([third.id, first.id, second.id], [thirdTrack.id, firstTrack.id, secondTrack.id])
    }

    @MainActor
    private func populateStore(at url: URL) throws -> (playlist: UUID, first: UUID, second: UUID) {
        let container = try PlaylistStorageService.createContainer(storeURL: url)
        let storage = PlaylistStorageService(context: container.mainContext)
        let playlist = try storage.createSection(name: "Library")
        let first = try append("One", to: playlist, using: storage)
        let second = try append("Two", to: playlist, using: storage)
        try storage.setTrackOrder([second.id, first.id], in: playlist)
        return (playlist.id, first.id, second.id)
    }

    @MainActor
    private func append(_ title: String, to playlist: Playlist, using storage: PlaylistStorageService) throws -> PlaylistTrack {
        try storage.appendTrack(
            title: title, artist: "Artist", url: URL(fileURLWithPath: "/Music/\(title).m4a"),
            bookmark: Data([1, 2]), duration: 125, artwork: Data([8, 9]), to: playlist
        )
    }
}
