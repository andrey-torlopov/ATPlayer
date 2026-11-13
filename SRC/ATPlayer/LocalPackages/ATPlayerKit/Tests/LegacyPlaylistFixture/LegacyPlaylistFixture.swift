import Foundation
import SwiftData

/// Creates a store with the original schema in another module, without depending on
/// the replacement persistence adapter. Keep these fixture models frozen.
public enum LegacyPlaylistFixture {
    public struct Contents {
        public let playlistIDs: [UUID]
        public let trackIDs: [UUID]
        public let bookmark: Data
        public let artwork: Data
        public let createdAt: Date
    }

    @MainActor
    public static func write(to url: URL) throws -> Contents {
        let container = try ModelContainer(
            for: TrackItem.self, PlaylistSection.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = container.mainContext
        context.autosaveEnabled = false
        let first = PlaylistSection(name: "Старая библиотека", order: 0)
        let second = PlaylistSection(name: "Старая библиотека", order: 1)
        context.insert(first)
        context.insert(second)
        let bookmark = Data([0, 255, 34, 17, 128])
        let artwork = Data([1, 127, 192, 255])
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let trackA = TrackItem(
            title: "Первый", artist: "Исполнитель", filePath: "/Music/первый.m4a",
            bookmark: bookmark, duration: 125.5, order: 1,
            isCorrupted: true, createdAt: createdAt, artwork: artwork
        )
        let trackB = TrackItem(
            title: "Второй", artist: "", filePath: "/Music/second.mp3",
            bookmark: Data([7, 8]), duration: 60, order: 0,
            createdAt: createdAt
        )
        trackA.section = first
        trackB.section = first
        context.insert(trackA)
        context.insert(trackB)
        try context.save()
        return Contents(
            playlistIDs: [first.id, second.id], trackIDs: [trackB.id, trackA.id],
            bookmark: bookmark, artwork: artwork, createdAt: createdAt
        )
    }
}
