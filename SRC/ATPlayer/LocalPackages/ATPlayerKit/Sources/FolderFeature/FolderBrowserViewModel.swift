import Combine
import FolderDomain
import Foundation

public struct FolderPlaybackSelection: Sendable {
    public let source: FolderSource
    public let entries: [FolderEntry]
    public let selectedID: UUID

    public init(source: FolderSource, entries: [FolderEntry], selectedID: UUID) {
        self.source = source
        self.entries = entries
        self.selectedID = selectedID
    }
}

@MainActor
public final class FolderBrowserViewModel: ObservableObject {
    public enum PreparationState: Equatable {
        case waiting
        case preparing
        case ready
        case failed(String)
    }

    @Published public private(set) var sources: [FolderSource] = []
    @Published public private(set) var source: FolderSource?
    @Published public private(set) var relativePath = ""
    @Published public private(set) var entries: [FolderEntry] = []
    @Published public private(set) var preparation: [UUID: PreparationState] = [:]
    @Published public private(set) var isLoading = false
    @Published public private(set) var isUpdatingSources = false
    @Published public var errorMessage: String?
    @Published public var showPicker = false

    private let store: any FolderSourceStoring
    private let access: any FolderAccessing
    private let onPlay: @MainActor (FolderPlaybackSelection) -> Void
    private let onRemoveSource: @MainActor (UUID) -> Void
    private var generation = UUID()
    private var isActive = false
    private var loadedSources = false
    private var loadingTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var mutationTask: Task<Void, Never>?

    public init(
        store: any FolderSourceStoring,
        access: any FolderAccessing,
        onPlay: @escaping @MainActor (FolderPlaybackSelection) -> Void,
        onRemoveSource: @escaping @MainActor (UUID) -> Void
    ) {
        self.store = store
        self.access = access
        self.onPlay = onPlay
        self.onRemoveSource = onRemoveSource
    }

    deinit {
        loadingTask?.cancel()
        prefetchTask?.cancel()
        mutationTask?.cancel()
    }

    public var pathTitle: String {
        guard let source else { return "Мои папки" }
        return relativePath.isEmpty ? source.name : "\(source.name) / \(relativePath)"
    }

    public func refresh() {
        isActive = true
        loadCurrentDirectory()
    }

    public func suspend() {
        isActive = false
        invalidateLoading()
        isLoading = false
    }

    public func open(_ source: FolderSource) {
        self.source = source
        relativePath = ""
        entries = []
        errorMessage = nil
        isActive = true
        loadCurrentDirectory()
    }

    public func open(_ entry: FolderEntry) {
        guard entry.kind == .directory, source != nil else { return }
        relativePath = entry.relativePath
        entries = []
        errorMessage = nil
        loadCurrentDirectory()
    }

    public func goBack() {
        guard source != nil else { return }
        if relativePath.isEmpty {
            source = nil
        } else {
            var components = relativePath.split(separator: "/")
            components.removeLast()
            relativePath = components.joined(separator: "/")
        }
        entries = []
        errorMessage = nil
        loadCurrentDirectory()
    }

    public func play(_ entry: FolderEntry) {
        guard let source, entry.kind == .audio,
              entries.contains(where: { $0.id == entry.id }) else { return }
        // Let the shared playback owner request this file with playback priority.
        prefetchTask?.cancel()
        prefetchTask = nil
        onPlay(FolderPlaybackSelection(
            source: source,
            entries: entries.filter { $0.kind == .audio },
            selectedID: entry.id
        ))
        startPrefetch(excludingID: entry.id)
    }

    public func importFolder(_ result: Result<[URL], Error>) {
        switch result {
        case let .failure(error):
            if (error as? CocoaError)?.code != .userCancelled {
                errorMessage = "Не удалось открыть выбранную папку. Повторите попытку."
            }
        case let .success(urls):
            guard !isUpdatingSources, let url = urls.first else { return }
            isUpdatingSources = true
            let requestID = generation
            mutationTask = Task { [weak self] in
                guard let self else { return }
                defer { self.isUpdatingSources = false; self.mutationTask = nil }
                do {
                    let source = try await self.access.makeSource(at: url)
                    let listing = try await self.access.list(source: source, relativePath: "")
                    try Task.checkCancellation()
                    if self.isCurrent(requestID) { self.errorMessage = nil }
                    // The access service excludes subtrees without supported audio.
                    // An empty result must not create a durable root or replace navigation.
                    guard !listing.entries.isEmpty else { return }
                    self.sources = try await self.store.upsert(listing.source)
                    self.loadedSources = true
                    if self.isCurrent(requestID), let saved = self.sources.first(where: { $0.id == source.id }) {
                        self.invalidateLoading()
                        self.isLoading = false
                        self.show(FolderListing(source: saved, relativePath: "", entries: listing.entries))
                    }
                } catch is CancellationError {
                    return
                } catch {
                    if self.isCurrent(requestID) { self.errorMessage = self.message(for: error) }
                }
            }
        }
    }

    public func remove(_ source: FolderSource) {
        guard !isUpdatingSources else { return }
        isUpdatingSources = true
        if self.source?.id == source.id { invalidateLoading() }
        mutationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isUpdatingSources = false; self.mutationTask = nil }
            do {
                self.sources = try await self.store.remove(id: source.id)
                self.onRemoveSource(source.id)
                if self.source?.id == source.id {
                    self.source = nil
                    self.relativePath = ""
                    self.entries = []
                    self.preparation = [:]
                    self.isLoading = false
                }
                await self.access.forget(sourceID: source.id)
            } catch {
                self.errorMessage = self.message(for: error)
                self.isLoading = false
            }
        }
    }

    private func loadCurrentDirectory() {
        invalidateLoading()
        guard isActive else { return }
        let requestID = generation
        let requestedSource = source
        let requestedPath = relativePath
        isLoading = true
        errorMessage = nil
        loadingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == requestID {
                    self.isLoading = false
                    self.loadingTask = nil
                }
            }
            do {
                if !self.loadedSources {
                    let saved = try await self.store.load()
                    guard self.isCurrent(requestID) else { return }
                    self.sources = saved
                    self.loadedSources = true
                }
                guard let requestedSource else { return }
                guard self.sources.contains(where: { $0.id == requestedSource.id }) else { return }
                let listing = try await self.access.list(source: requestedSource, relativePath: requestedPath)
                guard self.isCurrent(requestID) else { return }
                guard self.sources.contains(where: { $0.id == requestedSource.id }) else { return }
                if listing.source != requestedSource {
                    let saved = try await self.store.updateExisting(listing.source)
                    guard self.isCurrent(requestID) else { return }
                    guard let refreshed = saved.first(where: { $0.id == requestedSource.id }),
                          let index = self.sources.firstIndex(where: { $0.id == requestedSource.id }) else { return }
                    // Another root may have been added/removed while awaiting the store.
                    // Merge only this bookmark, never replace a newer roots snapshot.
                    self.sources[index] = refreshed
                }
                self.show(listing)
            } catch is CancellationError {
                return
            } catch {
                guard self.isCurrent(requestID) else { return }
                self.errorMessage = self.message(for: error)
            }
        }
    }

    private func show(_ listing: FolderListing) {
        source = listing.source
        relativePath = listing.relativePath
        entries = listing.entries
        preparation = Dictionary(uniqueKeysWithValues: listing.entries.filter { $0.kind == .audio }.map { ($0.id, .waiting) })
        startPrefetch()
    }

    private func startPrefetch(excludingID: UUID? = nil) {
        prefetchTask?.cancel()
        preparation = preparation.mapValues { $0 == .preparing ? .waiting : $0 }
        guard isActive, let source else { return }
        let requestID = generation
        let audio = entries.filter { $0.kind == .audio && $0.id != excludingID }
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            for entry in audio {
                guard self.isCurrent(requestID), !Task.isCancelled else { return }
                if self.preparation[entry.id] == .ready { continue }
                self.preparation[entry.id] = .preparing
                do {
                    let lease = try await self.access.prepare(source: source, entry: entry, priority: .prefetch)
                    await self.access.release(lease)
                    guard self.isCurrent(requestID), !Task.isCancelled else { return }
                    self.preparation[entry.id] = .ready
                } catch is CancellationError {
                    return
                } catch {
                    guard self.isCurrent(requestID), !Task.isCancelled else { return }
                    self.preparation[entry.id] = .failed(self.message(for: error))
                }
            }
        }
    }

    private func invalidateLoading() {
        generation = UUID()
        loadingTask?.cancel()
        loadingTask = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        preparation = preparation.mapValues { $0 == .preparing ? .waiting : $0 }
    }

    private func isCurrent(_ requestID: UUID) -> Bool { isActive && generation == requestID && !Task.isCancelled }

    private func message(for error: Error) -> String {
        if let error = error as? FolderAccessError { return error.localizedDescription }
        if let error = error as? FolderSourceStoreError { return error.localizedDescription }
        return "Не удалось открыть папку или подготовить файл. Проверьте доступ и повторите попытку."
    }

    // Tests await the actual owned tasks, without timing sleeps.
    func waitForCurrentLoad() async { await loadingTask?.value }
    var currentLoadCompletion: Task<Void, Never>? { loadingTask }
    func waitForPrefetch() async { await prefetchTask?.value }
    func waitForSourceMutation() async { await mutationTask?.value }
}
