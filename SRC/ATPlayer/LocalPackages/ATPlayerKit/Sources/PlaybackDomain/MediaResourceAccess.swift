import AppLocalization
import Foundation

/// Metadata read from an audio resource, independent of AVFoundation and storage.
public struct MediaMetadata: Sendable {
    public let title: String
    public let artist: String
    public let duration: Double
    public let artwork: Data?

    public init(title: String, artist: String, duration: Double, artwork: Data?) {
        self.title = title
        self.artist = artist
        self.duration = duration
        self.artwork = artwork
    }
}

/// The caller owns `scopedURL` until it calls `releaseAccess(to:)`.
public struct ImportMediaResource: Sendable {
    public let url: URL
    public let directoryURL: URL?
    public let scopedURL: URL?

    public init(url: URL, directoryURL: URL?, scopedURL: URL?) {
        self.url = url
        self.directoryURL = directoryURL
        self.scopedURL = scopedURL
    }
}

/// A resolved file plus any bookmark refresh that the repository must persist.
/// The caller owns `scopedURL` on success, including if persisting the refresh fails.
public struct ResolvedMediaResource: Sendable {
    public let url: URL
    public let scopedURL: URL?
    public let refreshedBookmark: Data?

    public init(url: URL, scopedURL: URL?, refreshedBookmark: Data?) {
        self.url = url
        self.scopedURL = scopedURL
        self.refreshedBookmark = refreshedBookmark
    }
}

public enum MediaResourceError: LocalizedError, Sendable {
    case importAccessDenied(fileName: String)
    case cloudDownloadFailed(fileName: String)
    case cloudDownloadTimedOut(fileName: String)

    public var errorDescription: String? {
        switch self {
        case let .importAccessDenied(fileName):
            L10n.format("Нет доступа к «%@». Выберите файл повторно.", fileName)
        case let .cloudDownloadFailed(fileName):
            L10n.format("Не удалось загрузить «%@». Проверьте доступ к iCloud.", fileName)
        case let .cloudDownloadTimedOut(fileName):
            L10n.format("Время ожидания загрузки «%@» из iCloud истекло.", fileName)
        }
    }
}

/// Filesystem and media access used by playlist import and playback.
/// Repository writes and the currently active playback request belong to the caller.
@MainActor
public protocol MediaResourceAccess: AnyObject {
    func openImportResource(at url: URL) throws -> ImportMediaResource
    func releaseAccess(to scopedURL: URL?)
    func makeBookmark(for url: URL, directoryURL: URL?) throws -> Data
    func resolve(bookmark: Data, filePath: String) throws -> ResolvedMediaResource

    /// Returns false when cancelled or superseded; download failures throw a localized error.
    func ensureDownloaded(
        _ url: URL,
        isCurrent: @escaping @MainActor () -> Bool
    ) async throws -> Bool

    func metadata(at url: URL) async throws -> MediaMetadata

    /// Recursive collection is retained for the existing playlist-import scenario.
    func collectAudioFiles(in directoryURL: URL) async -> [URL]
}
