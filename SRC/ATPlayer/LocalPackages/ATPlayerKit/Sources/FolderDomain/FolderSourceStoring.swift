import Foundation

/// Mutations are atomic within the store. Only user-selected roots are persisted.
public protocol FolderSourceStoring: Sendable {
    func load() async throws -> [FolderSource]
    func upsert(_ source: FolderSource) async throws -> [FolderSource]
    func updateExisting(_ source: FolderSource) async throws -> [FolderSource]
    func remove(id: UUID) async throws -> [FolderSource]
}

public enum FolderSourceStoreError: LocalizedError, Sendable {
    case unreadable
    case unsupportedFormat
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .unreadable:
            "Не удалось прочитать сохранённые папки. Повторите попытку."
        case .unsupportedFormat:
            "Список сохранённых папок имеет неподдерживаемый формат."
        case .writeFailed:
            "Не удалось сохранить список папок. Проверьте свободное место и повторите попытку."
        }
    }
}
