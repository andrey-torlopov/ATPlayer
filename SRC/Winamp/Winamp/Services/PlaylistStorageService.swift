import Foundation
import SwiftData

@MainActor
final class PlaylistStorageService {
    private let context: ModelContext

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
        let nextOrder = try fetchSections().count
        let section = PlaylistSection(name: name, order: nextOrder)
        context.insert(section)
        try context.save()
        return section
    }

    func removeSection(_ section: PlaylistSection) throws {
        context.delete(section)
        try normalizeSectionOrder()
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
        to section: PlaylistSection
    ) throws -> TrackItem {
        let nextOrder = section.tracks.count
        let item = TrackItem(
            title: title,
            artist: artist,
            filePath: url.path,
            bookmark: bookmark,
            duration: duration,
            order: nextOrder
        )
        item.section = section
        context.insert(item)
        try context.save()
        return item
    }

    func markCorrupted(_ track: TrackItem) throws {
        track.isCorrupted = true
        try context.save()
    }

    func removeTrack(_ track: TrackItem) throws {
        let section = track.section
        context.delete(track)
        try context.save()
        if let section {
            normalizeTrackOrder(in: section)
            try context.save()
        }
    }

    // MARK: - Ordering

    private func normalizeSectionOrder() throws {
        let sections = try fetchSections()
        for (index, section) in sections.enumerated() {
            section.order = index
        }
        try context.save()
    }

    private func normalizeTrackOrder(in section: PlaylistSection) {
        let sorted = section.tracks.sorted { $0.order < $1.order }
        for (index, track) in sorted.enumerated() {
            track.order = index
        }
    }
}
