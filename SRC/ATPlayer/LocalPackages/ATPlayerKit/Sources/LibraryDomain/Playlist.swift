import Foundation

/// In-memory library state. Persistence identities and metadata are mapped by the repository.
@MainActor
public final class Playlist: Identifiable {
    public nonisolated let id: UUID
    public var name: String
    public var order: Int
    public var tracks: [PlaylistTrack]

    public init(id: UUID = UUID(), name: String, order: Int, tracks: [PlaylistTrack] = []) {
        self.id = id
        self.name = name
        self.order = order
        self.tracks = tracks
        for track in tracks { track.section = self }
    }
}

@MainActor
public final class PlaylistTrack: Identifiable {
    public nonisolated let id: UUID
    public var title: String
    public var artist: String
    public var filePath: String
    public var bookmark: Data
    public var duration: Double
    public var order: Int
    public var isCorrupted: Bool
    public var createdAt: Date
    public var artwork: Data?
    public weak var section: Playlist?

    public init(
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

    public var displayName: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
        }
        return trimmedTitle
    }

    public var displayArtist: String? {
        let value = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.caseInsensitiveCompare("Unknown Artist") != .orderedSame else {
            return nil
        }
        return value
    }

    public var displayTitle: String {
        guard let artist = displayArtist else { return displayName }
        return "\(artist) - \(displayName)"
    }

    public var durationText: String {
        guard duration.isFinite, duration > 0, duration < Double(Int.max) else { return "--:--" }
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):" + String(format: "%02d", seconds)
    }
}
