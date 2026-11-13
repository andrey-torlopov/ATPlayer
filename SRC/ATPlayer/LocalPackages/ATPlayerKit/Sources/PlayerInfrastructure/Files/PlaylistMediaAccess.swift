import AVFoundation
import Foundation
import PlaybackDomain

@MainActor
public final class PlaylistMediaAccess: MediaResourceAccess {
    // Keep the existing persisted envelope compatible with raw legacy bookmarks.
    private struct TrackBookmark: Codable {
        var file: Data
        var directory: Data?
    }

    private static let cloudDownloadAttempts = 120
    private static let cloudDownloadPollInterval: Duration = .milliseconds(500)
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func openImportResource(at url: URL) throws -> ImportMediaResource {
        let didAccess = url.startAccessingSecurityScopedResource()
        guard didAccess || fileManager.isReadableFile(atPath: url.path) else {
            throw MediaResourceError.importAccessDenied(fileName: url.lastPathComponent)
        }
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return ImportMediaResource(
            url: url,
            directoryURL: exists && isDirectory.boolValue ? url : nil,
            scopedURL: didAccess ? url : nil
        )
    }

    public func releaseAccess(to scopedURL: URL?) {
        scopedURL?.stopAccessingSecurityScopedResource()
    }

    public func makeBookmark(for url: URL, directoryURL: URL?) throws -> Data {
        let bookmark = TrackBookmark(
            file: try url.bookmarkData(options: .minimalBookmark),
            directory: try directoryURL?.bookmarkData(options: .minimalBookmark)
        )
        return try JSONEncoder().encode(bookmark)
    }

    public func resolve(bookmark data: Data, filePath: String) throws -> ResolvedMediaResource {
        var bookmark = (try? JSONDecoder().decode(TrackBookmark.self, from: data))
            ?? TrackBookmark(file: data, directory: nil)
        var scopedURL: URL?
        do {
            var directoryStale = false
            if let directoryData = bookmark.directory {
                let directoryURL = try URL(
                    resolvingBookmarkData: directoryData,
                    bookmarkDataIsStale: &directoryStale
                )
                if directoryURL.startAccessingSecurityScopedResource() {
                    scopedURL = directoryURL
                } else if !fileManager.isReadableFile(atPath: directoryURL.path) {
                    throw CocoaError(.fileReadNoPermission)
                }
                if directoryStale {
                    bookmark.directory = try directoryURL.bookmarkData(options: .minimalBookmark)
                }
            }
            var fileStale = false
            let url = try URL(resolvingBookmarkData: bookmark.file, bookmarkDataIsStale: &fileStale)
            if scopedURL == nil, url.startAccessingSecurityScopedResource() {
                scopedURL = url
            }
            if fileStale {
                bookmark.file = try url.bookmarkData(options: .minimalBookmark)
            }
            let refreshedBookmark = fileStale || directoryStale || filePath != url.path
                ? try JSONEncoder().encode(bookmark) : nil
            return ResolvedMediaResource(
                url: url,
                scopedURL: scopedURL,
                refreshedBookmark: refreshedBookmark
            )
        } catch {
            releaseAccess(to: scopedURL)
            throw error
        }
    }

    public func ensureDownloaded(
        _ url: URL,
        isCurrent: @escaping @MainActor () -> Bool
    ) async throws -> Bool {
        func canContinue() -> Bool {
            !Task.isCancelled && isCurrent()
        }
        guard canContinue() else { return false }
        guard !isDownloaded(url) else { return true }
        do {
            try fileManager.startDownloadingUbiquitousItem(at: url)
        } catch {
            guard canContinue() else { return false }
            throw MediaResourceError.cloudDownloadFailed(fileName: url.lastPathComponent)
        }
        for _ in 0..<Self.cloudDownloadAttempts {
            guard canContinue() else { return false }
            do {
                try await Task.sleep(for: Self.cloudDownloadPollInterval)
            } catch {
                return false
            }
            guard canContinue() else { return false }
            if isDownloaded(url) { return true }
        }
        guard canContinue() else { return false }
        throw MediaResourceError.cloudDownloadTimedOut(fileName: url.lastPathComponent)
    }

    public func metadata(at url: URL) async throws -> MediaMetadata {
        // Keep the security scope alive in the caller while decoding off MainActor.
        let validation = Task.detached(priority: .userInitiated) {
            try AudioFileValidator.validate(url) { try Task.checkCancellation() }
        }
        let duration = try await withTaskCancellationHandler {
            try await validation.value
        } onCancel: {
            validation.cancel()
        }
        try Task.checkCancellation()
        let asset = AVURLAsset(url: url)
        let fallbackName = url.deletingPathExtension().lastPathComponent
        let metadataItems = (try? await asset.load(.commonMetadata)) ?? []

        let titleItem = AVMetadataItem.metadataItems(
            from: metadataItems,
            filteredByIdentifier: .commonIdentifierTitle
        ).first
        let artistItem = AVMetadataItem.metadataItems(
            from: metadataItems,
            filteredByIdentifier: .commonIdentifierArtist
        ).first
        let artworkItem = AVMetadataItem.metadataItems(
            from: metadataItems,
            filteredByIdentifier: .commonIdentifierArtwork
        ).first

        let titleValue = try? await titleItem?.load(.stringValue)
        let artistValue = try? await artistItem?.load(.stringValue)
        let artwork = try? await artworkItem?.load(.dataValue)
        let title = titleValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = artistValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return MediaMetadata(
            title: title.isEmpty ? fallbackName : title,
            artist: artist,
            duration: duration,
            artwork: artwork
        )
    }

    public func collectAudioFiles(in directoryURL: URL) async -> [URL] {
        var result: [URL] = []
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .ubiquitousItemDownloadingStatusKey],
            options: [.skipsHiddenFiles]
        ) else { return result }

        while let fileURL = enumerator.nextObject() as? URL {
            await Task.yield()
            guard !Task.isCancelled else { break }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true,
               SupportedAudioFormats.contains(fileURL) {
                result.append(fileURL)
            }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func isDownloaded(_ url: URL) -> Bool {
        do {
            var resourceURL = url
            resourceURL.removeCachedResourceValue(forKey: .ubiquitousItemDownloadingStatusKey)
            let values = try resourceURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            let status = values.ubiquitousItemDownloadingStatus
            return status == .current || status == .downloaded
                || (status == nil && fileManager.isReadableFile(atPath: url.path))
        } catch {
            return fileManager.isReadableFile(atPath: url.path)
        }
    }
}
