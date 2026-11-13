import Foundation
import LegacyPlaylistFixture
import LibraryDomain
import SwiftData
import XCTest
@testable import PlayerInfrastructure

final class LegacyPlaylistCompatibilityTests: XCTestCase {
    @MainActor
    func testOriginalSchemaOpensAfterModuleRelocation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("default.store")
        let expected = try LegacyPlaylistFixture.write(to: url)

        let container = try PlaylistStorageService.createContainer(storeURL: url)
        let storage = PlaylistStorageService(context: container.mainContext)
        let playlists = try storage.fetchSections()
        XCTAssertEqual(playlists.map(\.id), expected.playlistIDs, "Existing playlist IDs and saved order must survive the module move.")
        XCTAssertEqual(playlists.map(\.name), ["Старая библиотека", "Старая библиотека"])
        let playlist = try XCTUnwrap(playlists.first)
        let tracks = storage.sortedTracks(in: playlist)
        XCTAssertEqual(tracks.map(\.id), expected.trackIDs, "Relationships and explicit track order must remain intact.")
        let track = try XCTUnwrap(tracks.last)
        XCTAssertEqual(track.title, "Первый")
        XCTAssertEqual(track.artist, "Исполнитель")
        XCTAssertEqual(track.filePath, "/Music/первый.m4a")
        XCTAssertEqual(track.bookmark, expected.bookmark)
        XCTAssertEqual(track.artwork, expected.artwork)
        XCTAssertEqual(track.createdAt, expected.createdAt)
        XCTAssertEqual(track.duration, 125.5)
        XCTAssertTrue(track.isCorrupted)
        XCTAssertTrue(track.section === playlist)
        XCTAssertEqual(playlists.last?.tracks.count, 0)

        // Read compatibility alone is insufficient: the relocated model must save too.
        try storage.renameSection(playlist, to: "Обновлённая библиотека")
        try storage.setTrackOrder(tracks.reversed().map(\.id), in: playlist)
        try storage.setCorrupted(false, for: track)
        let reopened = try PlaylistStorageService.createContainer(storeURL: url)
        let reopenedStorage = PlaylistStorageService(context: reopened.mainContext)
        let saved = try XCTUnwrap(reopenedStorage.fetchSections().first)
        XCTAssertEqual(saved.name, "Обновлённая библиотека")
        XCTAssertEqual(reopenedStorage.sortedTracks(in: saved).map(\.id), expected.trackIDs.reversed().map { $0 })
        XCTAssertEqual(reopenedStorage.sortedTracks(in: saved).first?.isCorrupted, false)
    }
}
