import Foundation
import SwiftData

@MainActor
final class PlaylistStorageService {
    private let context: ModelContext

    private enum StorageError: Error {
        case invalidTrackOrder
    }

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Sections

    func fetchSections() throws -> [PlaylistSection] {
        let descriptor = FetchDescriptor<PlaylistSection>(
            sortBy: [SortDescriptor(\PlaylistSection.order)]
        )
        return try context.fetch(descriptor)
    }

    func createSection(name: String) throws -> PlaylistSection {
        let nextOrder = (try fetchSections().map(\.order).max() ?? -1) + 1
        let section = PlaylistSection(name: name, order: nextOrder)
        context.insert(section)
        try saveChanges()
        return section
    }

    func removeSection(_ section: PlaylistSection) throws {
        let remaining = try fetchSections().filter { $0.id != section.id }
        context.delete(section)
        for (index, remainingSection) in remaining.enumerated() {
            remainingSection.order = index
        }
        try saveChanges()
    }

    func renameSection(_ section: PlaylistSection, to name: String) throws {
        section.name = name
        try saveChanges()
    }

    func ensureDefaultSection() throws -> PlaylistSection {
        let sections = try fetchSections()
        if let first = sections.first {
            return first
        }
        return try createSection(name: "My Music")
    }

    // MARK: - Tracks

    func sortedTracks(in section: PlaylistSection) -> [TrackItem] {
        section.tracks.sorted { $0.order < $1.order }
    }

    func appendTrack(
        title: String,
        artist: String,
        url: URL,
        bookmark: Data,
        duration: Double,
        artwork: Data?,
        to section: PlaylistSection
    ) throws -> TrackItem {
        let nextOrder = (section.tracks.map(\.order).max() ?? -1) + 1
        let item = TrackItem(
            title: title,
            artist: artist,
            filePath: url.path,
            bookmark: bookmark,
            duration: duration,
            order: nextOrder,
            artwork: artwork
        )
        item.section = section
        context.insert(item)
        try saveChanges()
        return item
    }

    func setCorrupted(_ isCorrupted: Bool, for track: TrackItem) throws {
        track.isCorrupted = isCorrupted
        try saveChanges()
    }

    func updateBookmark(for track: TrackItem, bookmark: Data, url: URL) throws {
        track.bookmark = bookmark
        track.filePath = url.path
        try saveChanges()
    }

    func removeTrack(_ track: TrackItem) throws {
        if let section = track.section {
            try removeTracks(withIDs: [track.id], from: section)
        } else {
            context.delete(track)
            try saveChanges()
        }
    }

    func removeTracks(withIDs trackIDs: Set<UUID>, from section: PlaylistSection) throws {
        let tracks = sortedTracks(in: section)
        let removed = tracks.filter { trackIDs.contains($0.id) }
        guard !removed.isEmpty else { return }
        let remaining = tracks.filter { !trackIDs.contains($0.id) }
        for track in removed {
            context.delete(track)
        }
        for (index, remainingTrack) in remaining.enumerated() {
            remainingTrack.order = index
        }
        try saveChanges()
    }

    func setTrackOrder(_ trackIDs: [UUID], in section: PlaylistSection) throws {
        let tracks = sortedTracks(in: section)
        guard trackIDs.count == tracks.count,
              Set(trackIDs) == Set(tracks.map(\.id)) else {
            throw StorageError.invalidTrackOrder
        }
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        for (index, trackID) in trackIDs.enumerated() {
            tracksByID[trackID]?.order = index
        }
        try saveChanges()
    }

    private func saveChanges() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
