import FolderDomain
import Foundation

/// Separate from the playlist schema: this file contains bookmarks for roots, never
/// directory contents, browsing paths, playback queues or cached audio locations.
public actor FolderSourceStore: FolderSourceStoring {
    private struct Document: Codable {
        let version: Int
        let sources: [FolderSource]
    }

    private let url: URL

    public init(url: URL = URL.applicationSupportDirectory
        .appendingPathComponent("ATPlayer", isDirectory: true)
        .appendingPathComponent("folder-sources.json")) {
        self.url = url
    }

    public func load() throws -> [FolderSource] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        } catch {
            throw FolderSourceStoreError.unreadable
        }
        guard document.version == 1,
              Set(document.sources.map(\.id)).count == document.sources.count else {
            throw FolderSourceStoreError.unsupportedFormat
        }
        return document.sources.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    public func upsert(_ source: FolderSource) throws -> [FolderSource] {
        var sources = try load()
        if let index = sources.firstIndex(where: { $0.id == source.id }) {
            var replacement = source
            replacement.order = sources[index].order
            sources[index] = replacement
        } else {
            var appended = source
            appended.order = sources.count
            sources.append(appended)
        }
        try write(sources)
        return sources
    }

    public func remove(id: UUID) throws -> [FolderSource] {
        var sources = try load().filter { $0.id != id }
        for index in sources.indices { sources[index].order = index }
        try write(sources)
        return sources
    }

    public func updateExisting(_ source: FolderSource) throws -> [FolderSource] {
        var sources = try load()
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return sources }
        var replacement = source
        replacement.order = sources[index].order
        sources[index] = replacement
        try write(sources)
        return sources
    }

    private func write(_ sources: [FolderSource]) throws {
        do {
            let data = try JSONEncoder().encode(Document(version: 1, sources: sources))
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            throw FolderSourceStoreError.writeFailed
        }
    }
}
