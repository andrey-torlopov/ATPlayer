import Foundation
import LibraryDomain
import SwiftData

@MainActor
public final class PlaylistStorageService: PlaylistStoring {
    private let context: ModelContext
    private var playlists: [UUID: Playlist] = [:]
    private var tracks: [UUID: PlaylistTrack] = [:]

    private enum StorageError: Error {
        case invalidTrackOrder
        case missingPlaylist
        case missingTrack
    }

    public init(context: ModelContext) {
        self.context = context
    }

    public static func createContainer(inMemory: Bool = false, storeURL: URL? = nil) throws -> ModelContainer {
        if let storeURL {
            return try ModelContainer(
                for: TrackItem.self, PlaylistSection.self,
                configurations: ModelConfiguration(url: storeURL)
            )
        }
        if inMemory {
            return try ModelContainer(
                for: TrackItem.self, PlaylistSection.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
        return try ModelContainer(for: TrackItem.self, PlaylistSection.self)
    }

    public func fetchSections() throws -> [Playlist] {
        let records = try fetchRecords()
        let validPlaylistIDs = Set(records.map(\.id))
        let validTrackIDs = Set(records.flatMap { $0.tracks.map(\.id) })
        playlists = playlists.filter { validPlaylistIDs.contains($0.key) }
        tracks = tracks.filter { validTrackIDs.contains($0.key) }

        return records.map { record in
            let playlist = playlists[record.id] ?? Playlist(id: record.id, name: record.name, order: record.order)
            playlists[record.id] = playlist
            playlist.name = record.name
            playlist.order = record.order
            playlist.tracks = record.tracks.map { item in
                let track = tracks[item.id] ?? PlaylistTrack(
                    id: item.id, title: item.title, artist: item.artist, filePath: item.filePath,
                    bookmark: item.bookmark, duration: item.duration, order: item.order,
                    isCorrupted: item.isCorrupted, createdAt: item.createdAt, artwork: item.artwork
                )
                tracks[item.id] = track
                track.title = item.title
                track.artist = item.artist
                track.filePath = item.filePath
                track.bookmark = item.bookmark
                track.duration = item.duration
                track.order = item.order
                track.isCorrupted = item.isCorrupted
                track.createdAt = item.createdAt
                track.artwork = item.artwork
                track.section = playlist
                return track
            }
            return playlist
        }
    }

    public func createSection(name: String) throws -> Playlist {
        let nextOrder = (try fetchRecords().map(\.order).max() ?? -1) + 1
        let section = PlaylistSection(name: name, order: nextOrder)
        context.insert(section)
        try saveChanges()
        guard let result = playlists[section.id] else { throw StorageError.missingPlaylist }
        return result
    }

    public func removeSection(_ section: Playlist) throws {
        let record = try playlistRecord(id: section.id)
        let remaining = try fetchRecords().filter { $0.id != section.id }
        context.delete(record)
        for (index, remainingSection) in remaining.enumerated() {
            remainingSection.order = index
        }
        try saveChanges()
    }

    public func renameSection(_ section: Playlist, to name: String) throws {
        try playlistRecord(id: section.id).name = name
        try saveChanges(refreshSnapshots: false)
        playlists[section.id]?.name = name
        section.name = name
    }

    public func ensureDefaultSection() throws -> Playlist {
        if let first = try fetchSections().first { return first }
        return try createSection(name: "My Music")
    }

    public func sortedTracks(in section: Playlist) -> [PlaylistTrack] {
        section.tracks.sorted { $0.order < $1.order }
    }

    public func appendTrack(
        title: String,
        artist: String,
        url: URL,
        bookmark: Data,
        duration: Double,
        artwork: Data?,
        to section: Playlist
    ) throws -> PlaylistTrack {
        let record = try playlistRecord(id: section.id)
        let nextOrder = (record.tracks.map(\.order).max() ?? -1) + 1
        let item = TrackItem(
            title: title, artist: artist, filePath: url.path, bookmark: bookmark,
            duration: duration, order: nextOrder, artwork: artwork
        )
        item.section = record
        context.insert(item)
        try saveChanges(refreshSnapshots: false)
        // Import may append hundreds of tracks. Updating this one snapshot avoids
        // remapping every existing playlist and all metadata after every insertion.
        guard let playlist = playlists[section.id] else {
            _ = try fetchSections()
            guard let result = tracks[item.id] else { throw StorageError.missingTrack }
            return result
        }
        let result = PlaylistTrack(
            id: item.id, title: item.title, artist: item.artist, filePath: item.filePath,
            bookmark: item.bookmark, duration: item.duration, order: item.order,
            isCorrupted: item.isCorrupted, createdAt: item.createdAt, artwork: item.artwork
        )
        result.section = playlist
        tracks[result.id] = result
        playlist.tracks.append(result)
        return result
    }

    public func setCorrupted(_ isCorrupted: Bool, for track: PlaylistTrack) throws {
        try trackRecord(id: track.id).isCorrupted = isCorrupted
        try saveChanges(refreshSnapshots: false)
        tracks[track.id]?.isCorrupted = isCorrupted
        track.isCorrupted = isCorrupted
    }

    public func updateBookmark(for track: PlaylistTrack, bookmark: Data, url: URL) throws {
        let record = try trackRecord(id: track.id)
        record.bookmark = bookmark
        record.filePath = url.path
        try saveChanges(refreshSnapshots: false)
        tracks[track.id]?.bookmark = bookmark
        tracks[track.id]?.filePath = url.path
        track.bookmark = bookmark
        track.filePath = url.path
    }

    public func removeTrack(_ track: PlaylistTrack) throws {
        let record = try trackRecord(id: track.id)
        if let section = record.section {
            try removeTracks(withIDs: [track.id], fromRecord: section)
        } else {
            context.delete(record)
            try saveChanges()
        }
    }

    public func removeTracks(withIDs trackIDs: Set<UUID>, from section: Playlist) throws {
        try removeTracks(withIDs: trackIDs, fromRecord: playlistRecord(id: section.id))
    }

    public func setTrackOrder(_ trackIDs: [UUID], in section: Playlist) throws {
        let records = try playlistRecord(id: section.id).tracks
        guard trackIDs.count == records.count,
              Set(trackIDs) == Set(records.map(\.id)) else {
            throw StorageError.invalidTrackOrder
        }
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        for (index, trackID) in trackIDs.enumerated() {
            byID[trackID]?.order = index
        }
        try saveChanges()
    }

    private func fetchRecords() throws -> [PlaylistSection] {
        try context.fetch(FetchDescriptor<PlaylistSection>(sortBy: [SortDescriptor(\PlaylistSection.order)]))
    }

    private func playlistRecord(id: UUID) throws -> PlaylistSection {
        let descriptor = FetchDescriptor<PlaylistSection>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else { throw StorageError.missingPlaylist }
        return record
    }

    private func trackRecord(id: UUID) throws -> TrackItem {
        let descriptor = FetchDescriptor<TrackItem>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else { throw StorageError.missingTrack }
        return record
    }

    private func removeTracks(withIDs trackIDs: Set<UUID>, fromRecord section: PlaylistSection) throws {
        let records = section.tracks.sorted { $0.order < $1.order }
        let removed = records.filter { trackIDs.contains($0.id) }
        guard !removed.isEmpty else { return }
        let remaining = records.filter { !trackIDs.contains($0.id) }
        for track in removed { context.delete(track) }
        for (index, track) in remaining.enumerated() { track.order = index }
        try saveChanges()
    }

    private func saveChanges(refreshSnapshots: Bool = true) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            // Restore retained domain objects too; they must not expose an uncommitted edit.
            _ = try? fetchSections()
            throw error
        }
        if refreshSnapshots { _ = try fetchSections() }
    }
}
