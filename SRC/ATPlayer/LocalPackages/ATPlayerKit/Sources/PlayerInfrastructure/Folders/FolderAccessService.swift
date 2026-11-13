import CryptoKit
import Foundation
import OSLog
import FolderDomain
import PlaybackDomain

/// Selected roots are durable elsewhere; this actor owns only transient listings,
/// cache bookkeeping and leases. Blocking provider work runs on bounded worker queues.
public actor FolderAccessService: FolderAccessing {
    private struct CacheRecord {
        let url: URL
        let sourceID: UUID
        let entryID: UUID
        let bytes: Int64
        var accessedAt: Date
        var leases: Set<UUID>
        var forgotten = false
    }

    private struct Reservation {
        let bytes: Int64
        var workerFinished = false
        var abandoned = false
    }

    private struct CopiedFile: Sendable {
        let url: URL
        let bytes: Int64
        let entry: FolderEntry
    }

    private struct ActiveOperation {
        let sourceID: UUID?
        let cancel: @Sendable () -> Void
    }

    private let cacheDirectory: URL
    private let maximumCacheBytes: Int64
    private let operationTimeout: TimeInterval
    private let playbackQueue: OperationQueue
    private let prefetchQueue: OperationQueue
    private let discoveryQueue: OperationQueue
    private var cache: [String: CacheRecord] = [:]
    private var leases: [UUID: String] = [:]
    private var cacheAliases: [String: String] = [:]
    private var reservations: [UUID: Reservation] = [:]
    private var operations: [UUID: ActiveOperation] = [:]
    private var generations: [UUID: UInt] = [:]
    private var cacheInitialized = false

    private static let logger = Logger(subsystem: "dev.torlopov.atplayer.ios", category: "FolderCache")
    private static let entryKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isHiddenKey,
        .fileSizeKey, .contentModificationDateKey, .isPackageKey
    ]

    public init(
        cacheDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("ATPlayerFolderCache", isDirectory: true),
        maximumCacheBytes: Int64 = 512 * 1024 * 1024,
        operationTimeout: TimeInterval = 60
    ) {
        self.cacheDirectory = cacheDirectory
        self.maximumCacheBytes = max(1, maximumCacheBytes)
        self.operationTimeout = max(0.1, operationTimeout)
        playbackQueue = OperationQueue()
        playbackQueue.name = "ATPlayer.folderPlayback"
        // Foundation's coordinator waits at default QoS. A dedicated queue keeps
        // selected files independent of utility prefetch without a priority inversion.
        playbackQueue.qualityOfService = .default
        playbackQueue.maxConcurrentOperationCount = 1
        prefetchQueue = OperationQueue()
        prefetchQueue.name = "ATPlayer.folderPrefetch"
        prefetchQueue.qualityOfService = .utility
        prefetchQueue.maxConcurrentOperationCount = 1
        discoveryQueue = OperationQueue()
        discoveryQueue.name = "ATPlayer.folderDiscovery"
        discoveryQueue.qualityOfService = .default
        discoveryQueue.maxConcurrentOperationCount = 1
    }

    public func makeSource(at url: URL) async throws -> FolderSource {
        try await perform(sourceID: nil) { request in
            guard url.isFileURL else { throw FolderAccessError.invalidPath }
            return try Self.withAccess(to: url) {
                try request.coordinate(at: url, options: [.immediatelyAvailableMetadataOnly]) { coordinatedURL in
                    let values = try coordinatedURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard values.isDirectory == true, values.isSymbolicLink != true else {
                        throw FolderAccessError.invalidPath
                    }
                    return FolderSource(
                        name: coordinatedURL.lastPathComponent,
                        bookmark: try coordinatedURL.bookmarkData(options: .minimalBookmark)
                    )
                }
            }
        }
    }

    public func list(source: FolderSource, relativePath: String) async throws -> FolderListing {
        let generation = generations[source.id, default: 0]
        let listing: FolderListing = try await perform(sourceID: source.id) { request in
            try Self.withResolvedSource(source) { root, refreshedSource in
                let directory = try Self.validatedURL(root: root, relativePath: relativePath, isDirectory: true)
                let listing = try request.coordinate(at: directory, options: [.immediatelyAvailableMetadataOnly]) { coordinatedDirectory in
                    try Self.validateCoordinatedURL(coordinatedDirectory, inside: root)
                    let directoryValues = try coordinatedDirectory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true else {
                        throw FolderAccessError.invalidPath
                    }
                    let urls = try FileManager.default.contentsOfDirectory(
                        at: coordinatedDirectory, includingPropertiesForKeys: Array(Self.entryKeys),
                        options: [.skipsHiddenFiles]
                    )
                    let scanNonce = UUID()
                    var entries: [FolderEntry] = []
                    for url in urls {
                        try request.checkCancellation()
                        let values = try url.resourceValues(forKeys: Self.entryKeys)
                        guard values.isSymbolicLink != true, values.isHidden != true else { continue }
                        let kind: FolderEntry.Kind
                        if values.isDirectory == true, values.isPackage != true {
                            kind = .directory
                        } else if values.isRegularFile == true, SupportedAudioFormats.contains(url) {
                            kind = .audio
                        } else { continue }
                        let path = relativePath.isEmpty ? url.lastPathComponent : relativePath + "/" + url.lastPathComponent
                        entries.append(FolderEntry(
                            id: Self.stableID(sourceID: source.id, path: path), name: url.lastPathComponent,
                            relativePath: path, kind: kind, size: values.fileSize.map(Int64.init),
                            modifiedAt: values.contentModificationDate,
                            versionNonce: values.fileSize == nil || values.contentModificationDate == nil ? scanNonce : nil
                        ))
                    }
                    entries.sort {
                        if $0.kind != $1.kind { return $0.kind == .directory }
                        let comparison = $0.name.localizedStandardCompare($1.name)
                        return comparison == .orderedSame ? $0.relativePath < $1.relativePath : comparison == .orderedAscending
                    }
                    return FolderListing(source: refreshedSource, relativePath: relativePath, entries: entries)
                }
                var visible: [FolderEntry] = []
                for entry in listing.entries {
                    try request.checkCancellation()
                    if entry.kind == .directory {
                        do {
                            let child = try Self.validatedURL(root: root, relativePath: entry.relativePath, isDirectory: true)
                            guard try Self.containsAudio(in: child, root: root, request: request) else { continue }
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch FolderAccessError.timedOut {
                            throw FolderAccessError.timedOut
                        } catch {
                            // An unreadable descendant is unknown, not empty. Keep
                            // the directory so a provider outage cannot hide its music
                            // or prevent playback of accessible siblings.
                            try request.checkCancellation()
                        }
                    } else {
                        let child = root.appendingPathComponent(entry.relativePath)
                        guard try Self.isPlayableAudio(at: child, root: root, request: request) else { continue }
                    }
                    visible.append(entry)
                }
                return FolderListing(source: listing.source, relativePath: listing.relativePath, entries: visible)
            }
        }
        try Task.checkCancellation()
        guard generations[source.id, default: 0] == generation else { throw CancellationError() }
        return listing
    }

    public func prepare(source: FolderSource, entry: FolderEntry, priority: FolderPreparationPriority) async throws -> CachedAudioLease {
        try Task.checkCancellation()
        guard entry.kind == .audio,
              SupportedAudioFormats.contains(URL(fileURLWithPath: entry.name)) else {
            throw FolderAccessError.unsupportedFile
        }
        try Self.validateRelativePath(entry.relativePath, allowsEmpty: false)
        let generation = generations[source.id, default: 0]
        try initializeCacheIfNeeded()
        let requestedKey = Self.cacheKey(sourceID: source.id, entry: entry)
        let lookupKey = cacheAliases[requestedKey] ?? requestedKey
        if var record = cache[lookupKey], !record.forgotten {
            if FileManager.default.isReadableFile(atPath: record.url.path) {
                let lease = CachedAudioLease(url: record.url, entryID: entry.id)
                record.leases.insert(lease.id)
                record.accessedAt = .now
                cache[lookupKey] = record
                leases[lease.id] = lookupKey
                return lease
            }
            cache.removeValue(forKey: lookupKey)
        }

        let operationID = UUID()
        let requestedBytes = max(1, entry.size ?? maximumCacheBytes)
        if priority == .prefetch, requestedBytes > maximumCacheBytes { throw FolderAccessError.cacheCapacity }
        try makeRoom(for: requestedBytes, allowPlaybackOverflow: priority == .playback)
        let copyLimit = priority == .playback ? Int64.max : requestedBytes
        reservations[operationID] = Reservation(bytes: requestedBytes)
        let destination = cacheDirectory.appendingPathComponent(UUID().uuidString + "." + URL(fileURLWithPath: entry.name).pathExtension)
        let partial = cacheDirectory.appendingPathComponent(UUID().uuidString + ".partial")
        let request = FolderIORequest<CopiedFile>(discard: { value in
            Self.removeTemporaryFile(value.url)
        }, finished: { [weak self] in
            Task { await self?.workerFinished(operationID) }
        })
        operations[operationID] = ActiveOperation(sourceID: source.id, cancel: { request.cancel() })
        defer { operations.removeValue(forKey: operationID) }
        do {
            let queue = priority == .playback ? playbackQueue : prefetchQueue
            let copied = try await request.run(on: queue, timeout: operationTimeout) { request in
                try Self.copy(source: source, entry: entry, partial: partial, destination: destination,
                              maximumBytes: copyLimit, request: request)
            }
            do {
                try Task.checkCancellation()
                guard generations[source.id, default: 0] == generation else { throw CancellationError() }
                let key = Self.cacheKey(sourceID: source.id, entry: copied.entry)
                let lease: CachedAudioLease
                if var existing = cache[key], !existing.forgotten,
                   FileManager.default.isReadableFile(atPath: existing.url.path) {
                    Self.removeTemporaryFile(copied.url)
                    lease = CachedAudioLease(url: existing.url, entryID: entry.id)
                    existing.leases.insert(lease.id)
                    existing.accessedAt = .now
                    cache[key] = existing
                } else {
                    lease = CachedAudioLease(url: copied.url, entryID: entry.id)
                    cache[key] = CacheRecord(url: copied.url, sourceID: source.id, entryID: entry.id,
                                             bytes: copied.bytes, accessedAt: .now, leases: [lease.id])
                }
                leases[lease.id] = key
                cacheAliases[requestedKey] = key
                reservations.removeValue(forKey: operationID)
                return lease
            } catch {
                Self.removeTemporaryFile(copied.url)
                throw error
            }
        } catch {
            abandonReservation(operationID)
            if error is CancellationError { throw error }
            if let folderError = error as? FolderAccessError { throw folderError }
            throw Self.translate(error)
        }
    }

    public func release(_ lease: CachedAudioLease) async {
        guard let key = leases.removeValue(forKey: lease.id), var record = cache[key] else { return }
        record.leases.remove(lease.id)
        record.accessedAt = .now
        if record.forgotten, record.leases.isEmpty {
            Self.removeTemporaryFile(record.url)
            cache.removeValue(forKey: key)
        } else {
            cache[key] = record
        }
        // Playback may temporarily exceed the soft budget for a long recording or
        // old/new handoff leases; release reclaims all unpinned excess immediately.
        do { try makeRoom(for: 0, allowPlaybackOverflow: true) }
        catch { Self.logger.error("Deferred cache eviction failed; retrying on the next cache operation") }
    }

    public func forget(sourceID: UUID) async {
        generations[sourceID, default: 0] &+= 1
        for operation in operations.values where operation.sourceID == sourceID { operation.cancel() }
        for key in Array(cache.keys) {
            guard var record = cache[key], record.sourceID == sourceID else { continue }
            if record.leases.isEmpty {
                Self.removeTemporaryFile(record.url)
                cache.removeValue(forKey: key)
            } else {
                record.forgotten = true
                cache[key] = record
            }
        }
    }

    private func perform<Value: Sendable>(sourceID: UUID?,
                                         operation: @escaping @Sendable (FolderIORequest<Value>) throws -> Value) async throws -> Value {
        let id = UUID()
        let request = FolderIORequest<Value>()
        operations[id] = ActiveOperation(sourceID: sourceID, cancel: { request.cancel() })
        defer { operations.removeValue(forKey: id) }
        do {
            return try await request.run(on: discoveryQueue, timeout: operationTimeout, operation: operation)
        } catch {
            if error is CancellationError { throw error }
            if let folderError = error as? FolderAccessError { throw folderError }
            throw Self.translate(error)
        }
    }

    private func initializeCacheIfNeeded() throws {
        guard !cacheInitialized else { return }
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            // Cache state is intentionally not restored. Remove only our generated files,
            // never a user's audio or arbitrary children of an injected test directory.
            for url in try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
                let stem = url.deletingPathExtension().lastPathComponent
                if UUID(uuidString: stem) != nil { try FileManager.default.removeItem(at: url) }
            }
            cacheInitialized = true
        } catch { throw FolderAccessError.cacheWriteFailed }
    }

    private func makeRoom(for requestedBytes: Int64, allowPlaybackOverflow: Bool = false) throws {
        var occupied = cache.values.reduce(Int64(0)) { $0 + $1.bytes }
            + reservations.values.reduce(Int64(0)) { $0 + $1.bytes }
        let target = max(0, maximumCacheBytes - min(maximumCacheBytes, requestedBytes))
        let candidates = cache.filter { $0.value.leases.isEmpty }.sorted { $0.value.accessedAt < $1.value.accessedAt }
        for (key, record) in candidates where occupied > target {
            do { try FileManager.default.removeItem(at: record.url) }
            catch {
                guard (error as? CocoaError)?.code == .fileNoSuchFile else { throw FolderAccessError.cacheWriteFailed }
            }
            occupied -= record.bytes
            cache.removeValue(forKey: key)
        }
        guard allowPlaybackOverflow || occupied <= target else { throw FolderAccessError.cacheCapacity }
        cacheAliases = cacheAliases.filter { cache[$0.value] != nil }
    }

    private func workerFinished(_ id: UUID) {
        guard var reservation = reservations[id] else { return }
        if reservation.abandoned { reservations.removeValue(forKey: id) }
        else {
            reservation.workerFinished = true
            reservations[id] = reservation
        }
    }

    private func abandonReservation(_ id: UUID) {
        guard var reservation = reservations[id] else { return }
        if reservation.workerFinished { reservations.removeValue(forKey: id) }
        else {
            reservation.abandoned = true
            reservations[id] = reservation
        }
    }

    /// Validate contents outside directory metadata accessors: provider accessors
    /// must not be nested. Stop once a subtree contains one playable audio file.
    private static func containsAudio<Value>(in directory: URL, root: URL,
                                             request: FolderIORequest<Value>) throws -> Bool {
        let keys = entryKeys
        var pending = [directory]
        while let next = pending.popLast() {
            try request.checkCancellation()
            let scan = try request.coordinate(at: next, options: [.immediatelyAvailableMetadataOnly]) { coordinatedURL in
                try validateCoordinatedURL(coordinatedURL, inside: root)
                var currentURL = coordinatedURL
                currentURL.removeAllCachedResourceValues()
                let current = try currentURL.resourceValues(forKeys: keys)
                guard current.isDirectory == true, current.isSymbolicLink != true else {
                    throw FolderAccessError.invalidPath
                }
                guard current.isHidden != true, current.isPackage != true else { return ([URL](), [URL]()) }
                let children = try FileManager.default.contentsOfDirectory(
                    at: currentURL, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
                )
                var candidates: [URL] = []
                var directories: [URL] = []
                for child in children {
                    try request.checkCancellation()
                    let values = try child.resourceValues(forKeys: keys)
                    guard values.isSymbolicLink != true, values.isHidden != true else { continue }
                    if values.isRegularFile == true, SupportedAudioFormats.contains(child) {
                        candidates.append(child)
                    }
                    if values.isDirectory == true, values.isPackage != true { directories.append(child) }
                }
                return (candidates, directories)
            }
            for candidate in scan.0 {
                if try isPlayableAudio(at: candidate, root: root, request: request) { return true }
            }
            pending.append(contentsOf: scan.1)
        }
        return false
    }

    private static func isPlayableAudio<Value>(at url: URL, root: URL,
                                               request: FolderIORequest<Value>) throws -> Bool {
        do {
            return try request.coordinate(at: url, options: []) { coordinatedURL in
                try validateCoordinatedURL(coordinatedURL, inside: root)
                let values = try coordinatedURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { return false }
                _ = try AudioFileValidator.validate(coordinatedURL, checkCancellation: request.checkCancellation)
                return true
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch FolderAccessError.timedOut {
            throw FolderAccessError.timedOut
        } catch {
            // An invalid or unavailable file must not enter the queue or hide
            // other valid tracks. Cancellation still takes precedence.
            try request.checkCancellation()
            return false
        }
    }

    private static func withAccess<T>(to url: URL, operation: () throws -> T) throws -> T {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // App-container files have no security scope; an actual coordinated operation
        // determines access. Avoid isReadableFile as a download-readiness heuristic.
        return try operation()
    }

    private static func withResolvedSource<T>(_ source: FolderSource, operation: (URL, FolderSource) throws -> T) throws -> T {
        var stale = false
        let root = try URL(resolvingBookmarkData: source.bookmark, bookmarkDataIsStale: &stale)
        guard root.isFileURL else { throw FolderAccessError.invalidPath }
        return try withAccess(to: root) {
            var refreshed = source
            if stale { refreshed.bookmark = try root.bookmarkData(options: .minimalBookmark) }
            return try operation(root, refreshed)
        }
    }

    private static func validateRelativePath(_ path: String, allowsEmpty: Bool) throws {
        if path.isEmpty, allowsEmpty { return }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }) else {
            throw FolderAccessError.invalidPath
        }
    }

    private static func validatedURL(root: URL, relativePath: String, isDirectory: Bool) throws -> URL {
        try validateRelativePath(relativePath, allowsEmpty: isDirectory)
        let rootValues = try root.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else { throw FolderAccessError.invalidPath }
        var result = root
        let components = relativePath.split(separator: "/")
        for (index, component) in components.enumerated() {
            let directory = index < components.count - 1 || isDirectory
            result.appendPathComponent(String(component), isDirectory: directory)
            let values = try result.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isSymbolicLink != true, !directory || values.isDirectory == true else {
                throw FolderAccessError.invalidPath
            }
        }
        return result
    }

    private static func validateCoordinatedURL(_ url: URL, inside root: URL) throws {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let resolvedPath = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard resolvedPath == rootPath || resolvedPath.hasPrefix(rootPath + "/") else { throw FolderAccessError.invalidPath }
    }

    private static func stableID(sourceID: UUID, path: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data((sourceID.uuidString + "\0" + path).utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private static func cacheKey(sourceID: UUID, entry: FolderEntry) -> String {
        let version = [sourceID.uuidString, entry.relativePath, entry.size.map(String.init) ?? "unknown",
                       entry.modifiedAt.map { String($0.timeIntervalSinceReferenceDate.bitPattern) } ?? "unknown",
                       entry.versionNonce?.uuidString ?? ""].joined(separator: "\0")
        return SHA256.hash(data: Data(version.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func copy(source: FolderSource, entry: FolderEntry, partial: URL, destination: URL,
                             maximumBytes: Int64, request: FolderIORequest<CopiedFile>) throws -> CopiedFile {
        var completedURL: URL?
        defer {
            removeTemporaryFile(partial)
            if let completedURL { removeTemporaryFile(completedURL) }
        }
        let result = try withResolvedSource(source) { root, _ in
            let url = try validatedURL(root: root, relativePath: entry.relativePath, isDirectory: false)
            return try request.coordinate(at: url, options: []) { coordinatedURL in
                try validateCoordinatedURL(coordinatedURL, inside: root)
                let values = try coordinatedURL.resourceValues(forKeys: entryKeys)
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      SupportedAudioFormats.contains(coordinatedURL) else { throw FolderAccessError.unsupportedFile }
                if let size = values.fileSize, Int64(size) > maximumBytes { throw FolderAccessError.cacheCapacity }
                guard FileManager.default.createFile(atPath: partial.path, contents: nil) else { throw FolderAccessError.cacheWriteFailed }
                let input = try FileHandle(forReadingFrom: coordinatedURL)
                defer { try? input.close() }
                let output = try FileHandle(forWritingTo: partial)
                defer { try? output.close() }
                var copied: Int64 = 0
                let chunkSize = 256 * 1024
                while true {
                    try request.checkCancellation()
                    guard let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty else { break }
                    guard Int64(chunk.count) <= maximumBytes - copied else { throw FolderAccessError.cacheCapacity }
                    try output.write(contentsOf: chunk)
                    copied += Int64(chunk.count)
                }
                try request.checkCancellation()
                var currentURL = coordinatedURL
                currentURL.removeAllCachedResourceValues()
                let finalValues = try currentURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                // A writer that ignores file coordination can still replace/truncate
                // the source while it is copied. Never publish such a partial version.
                if let expectedSize = values.fileSize, copied != Int64(expectedSize) {
                    throw FolderAccessError.unavailable
                }
                if let finalSize = finalValues.fileSize, copied != Int64(finalSize) {
                    throw FolderAccessError.unavailable
                }
                if let before = values.contentModificationDate,
                   let after = finalValues.contentModificationDate, before != after {
                    throw FolderAccessError.unavailable
                }
                try output.synchronize()
                try output.close()
                try FileManager.default.moveItem(at: partial, to: destination)
                completedURL = destination
                try request.checkCancellation()
                do {
                    _ = try AudioFileValidator.validate(destination, checkCancellation: request.checkCancellation)
                } catch {
                    try request.checkCancellation()
                    throw FolderAccessError.unsupportedFile
                }
                let actualEntry = FolderEntry(
                    id: entry.id, name: entry.name, relativePath: entry.relativePath, kind: .audio,
                    size: Int64(values.fileSize ?? Int(copied)), modifiedAt: values.contentModificationDate,
                    versionNonce: values.fileSize == nil || values.contentModificationDate == nil ? entry.versionNonce : nil
                )
                return CopiedFile(url: destination, bytes: copied, entry: actualEntry)
            }
        }
        completedURL = nil
        return result
    }

    private static func translate(_ error: Error) -> FolderAccessError {
        let code = (error as NSError).code
        let domain = (error as NSError).domain
        if domain == NSCocoaErrorDomain,
           code == NSFileReadNoPermissionError || code == NSFileWriteNoPermissionError { return .accessDenied }
        return .unavailable
    }

    private static func removeTemporaryFile(_ url: URL) {
        do { try FileManager.default.removeItem(at: url) }
        catch {
            guard (error as? CocoaError)?.code != .fileNoSuchFile else { return }
            // Startup retries cleanup of owned temporary files. Never remove source files.
            logger.error("Temporary audio cache cleanup failed")
        }
    }
}
