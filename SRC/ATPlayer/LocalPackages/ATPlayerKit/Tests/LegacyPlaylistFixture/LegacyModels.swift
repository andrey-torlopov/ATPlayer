// Frozen pre-refactoring SwiftData schema, compiled in a separate module.
import Foundation
import SwiftData

@Model
final class PlaylistSection {
    @Attribute(.unique) var id: UUID
    var name: String
    var order: Int
    @Relationship(deleteRule: .cascade, inverse: \TrackItem.section)
    var tracks: [TrackItem]

    init(
        id: UUID = UUID(),
        name: String,
        order: Int,
        tracks: [TrackItem] = []
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.tracks = tracks
    }
}

@Model
final class TrackItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String
    var filePath: String
    var bookmark: Data
    var duration: Double
    var order: Int
    var isCorrupted: Bool
    var createdAt: Date
    var artwork: Data?
    var section: PlaylistSection?

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        filePath: String,
        bookmark: Data,
        duration: Double,
        order: Int,
        isCorrupted: Bool = false,
        createdAt: Date = .now,
        artwork: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.filePath = filePath
        self.bookmark = bookmark
        self.duration = duration
        self.order = order
        self.isCorrupted = isCorrupted
        self.createdAt = createdAt
        self.artwork = artwork
    }
}
