import AppLocalization
import Foundation

/// Only selected roots are durable. Directory listings and playback queues stay in memory.
public struct FolderSource: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var bookmark: Data
    public var order: Int

    public init(id: UUID = UUID(), name: String, bookmark: Data, order: Int = 0) {
        self.id = id
        self.name = name
        self.bookmark = bookmark
        self.order = order
    }
}

public struct FolderEntry: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case directory
        case audio
    }

    public let id: UUID
    public let name: String
    public let relativePath: String
    public let kind: Kind
    public let size: Int64?
    public let modifiedAt: Date?
    /// A fresh scan invalidates cache entries whose provider supplies no reliable version.
    public let versionNonce: UUID?

    public init(id: UUID, name: String, relativePath: String, kind: Kind,
                size: Int64? = nil, modifiedAt: Date? = nil, versionNonce: UUID? = nil) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.kind = kind
        self.size = size
        self.modifiedAt = modifiedAt
        self.versionNonce = versionNonce
    }
}

public struct FolderListing: Sendable {
    public let source: FolderSource
    public let relativePath: String
    public let entries: [FolderEntry]

    public init(source: FolderSource, relativePath: String, entries: [FolderEntry]) {
        self.source = source
        self.relativePath = relativePath
        self.entries = entries
    }
}

/// The caller releases a lease only after the audio engine has stopped reading this URL.
public struct CachedAudioLease: Sendable {
    public let id: UUID
    public let url: URL
    public let entryID: UUID

    public init(id: UUID = UUID(), url: URL, entryID: UUID) {
        self.id = id
        self.url = url
        self.entryID = entryID
    }
}

public enum FolderPreparationPriority: Sendable {
    case playback
    case prefetch
}

public enum FolderAccessError: LocalizedError, Sendable {
    case invalidPath
    case accessDenied
    case unavailable
    case timedOut
    case unsupportedFile
    case cacheCapacity
    case cacheWriteFailed

    public var errorDescription: String? {
        switch self {
        case .invalidPath:
            L10n.text("Недопустимый путь. Обновите папку или выберите её заново.")
        case .accessDenied:
            L10n.text("Нет доступа к папке. Выберите её заново через «Добавить папку».")
        case .unavailable:
            L10n.text("Файл или папка недоступны. Проверьте подключение и обновите список.")
        case .timedOut:
            L10n.text("Не удалось дождаться файлов. Проверьте сеть и повторите попытку.")
        case .unsupportedFile:
            L10n.text("Этот файл не поддерживается или является ссылкой. Обновите папку.")
        case .cacheCapacity:
            L10n.text("Недостаточно свободного места для подготовки файла. Освободите место на устройстве и повторите попытку.")
        case .cacheWriteFailed:
            L10n.text("Не удалось сохранить временную копию. Проверьте свободное место на устройстве.")
        }
    }
}

public protocol FolderAccessing: Sendable {
    func makeSource(at url: URL) async throws -> FolderSource
    /// Returns immediate audio files and directories whose visible subtree contains
    /// supported audio. Descendant tracks are neither returned nor prepared.
    func list(source: FolderSource, relativePath: String) async throws -> FolderListing
    func prepare(source: FolderSource, entry: FolderEntry, priority: FolderPreparationPriority) async throws -> CachedAudioLease
    func release(_ lease: CachedAudioLease) async
    func forget(sourceID: UUID) async
}
