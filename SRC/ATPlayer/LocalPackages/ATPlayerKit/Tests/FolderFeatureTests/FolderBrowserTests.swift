import FolderDomain
import Foundation
import XCTest
@testable import FolderFeature

final class FolderBrowserTests: XCTestCase {
    @MainActor
    func testSelectionContainsOnlyVisibleAudioAndNavigationDoesNotPlay() async throws {
        let source = FolderSource(name: "Root", bookmark: Data([1]))
        let directory = FolderEntry(id: UUID(), name: "Album", relativePath: "Album", kind: .directory)
        let first = FolderEntry(id: UUID(), name: "1.mp3", relativePath: "1.mp3", kind: .audio)
        let second = FolderEntry(id: UUID(), name: "2.mp3", relativePath: "2.mp3", kind: .audio)
        let nested = FolderEntry(id: UUID(), name: "nested.mp3", relativePath: "Album/nested.mp3", kind: .audio)
        let access = BrowserAccess(source: source, listings: ["": [directory, first, second], "Album": [nested]])
        let store = MemoryRoots([source])
        var selections: [FolderPlaybackSelection] = []
        let model = FolderBrowserViewModel(store: store, access: access, onPlay: { selections.append($0) }, onRemoveSource: { _ in })
        model.refresh()
        await model.waitForCurrentLoad()
        model.open(source)
        await model.waitForCurrentLoad()
        await model.waitForPrefetch()
        model.play(second)
        XCTAssertEqual(selections.count, 1)
        XCTAssertEqual(selections.first?.entries.map(\.id), [first.id, second.id])
        XCTAssertEqual(selections.first?.selectedID, second.id)
        model.open(directory)
        await model.waitForCurrentLoad()
        await model.waitForPrefetch()
        XCTAssertEqual(selections.count, 1, "Browsing another folder must not replace the active playback queue.")
        XCTAssertEqual(model.entries.map(\.id), [nested.id])
        let prepared = await access.preparedIDs()
        XCTAssertFalse(prepared.contains(directory.id), "Only audio files from opened levels may be prefetched.")
        let released = await access.releasedIDs()
        XCTAssertEqual(Set(prepared), Set(released), "Every successful browser prefetch must release its cache lease.")
        model.suspend()
    }

    @MainActor
    func testLateListingCannotReplaceNewDirectory() async throws {
        let source = FolderSource(name: "Root", bookmark: Data([1]))
        let directory = FolderEntry(id: UUID(), name: "Album", relativePath: "Album", kind: .directory)
        let nested = FolderEntry(id: UUID(), name: "nested.mp3", relativePath: "Album/nested.mp3", kind: .audio)
        let access = BrowserAccess(source: source, listings: ["": [directory], "Album": [nested]])
        let model = FolderBrowserViewModel(store: MemoryRoots([source]), access: access, onPlay: { _ in }, onRemoveSource: { _ in })
        model.refresh()
        await model.waitForCurrentLoad()
        await access.holdListing(at: "")
        model.open(source)
        await access.waitForHeldListing(at: "")
        let oldLoad = model.currentLoadCompletion
        model.open(directory)
        await model.waitForCurrentLoad()
        XCTAssertEqual(model.relativePath, "Album")
        await access.completeHeldListing(at: "")
        await oldLoad?.value
        await model.waitForPrefetch()
        XCTAssertEqual(model.relativePath, "Album")
        XCTAssertEqual(model.entries.map(\.id), [nested.id], "A non-cooperative old provider response must be ignored.")
        model.suspend()
    }

    @MainActor
    func testSuspendReleasesLatePrefetchAndDoesNotPublishReady() async throws {
        let source = FolderSource(name: "Root", bookmark: Data([1]))
        let audio = FolderEntry(id: UUID(), name: "Song", relativePath: "Song.mp3", kind: .audio)
        let access = BrowserAccess(source: source, listings: ["": [audio]])
        await access.holdPreparation(for: audio.id)
        let model = FolderBrowserViewModel(store: MemoryRoots([source]), access: access, onPlay: { _ in }, onRemoveSource: { _ in })
        model.refresh()
        await model.waitForCurrentLoad()
        model.open(source)
        await model.waitForCurrentLoad()
        await access.waitForHeldPreparation()
        model.suspend()
        await access.completeHeldPreparation()
        await access.waitForLeaseRelease()
        XCTAssertEqual(model.preparation[audio.id], .waiting)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testOnlyRootsReturnWhenNewBrowserIsCreated() async throws {
        let source = FolderSource(name: "Root", bookmark: Data([1]))
        let directory = FolderEntry(id: UUID(), name: "Album", relativePath: "Album", kind: .directory)
        let store = MemoryRoots([source])
        let access = BrowserAccess(source: source, listings: ["": [directory], "Album": []])
        let model = FolderBrowserViewModel(store: store, access: access, onPlay: { _ in }, onRemoveSource: { _ in })
        model.refresh()
        await model.waitForCurrentLoad()
        model.open(source)
        await model.waitForCurrentLoad()
        model.open(directory)
        await model.waitForCurrentLoad()
        model.suspend()
        let relaunched = FolderBrowserViewModel(store: store, access: access, onPlay: { _ in }, onRemoveSource: { _ in })
        relaunched.refresh()
        await relaunched.waitForCurrentLoad()
        XCTAssertEqual(relaunched.sources.map(\.id), [source.id])
        XCTAssertNil(relaunched.source)
        XCTAssertEqual(relaunched.relativePath, "")
        XCTAssertTrue(relaunched.entries.isEmpty)
        relaunched.suspend()
    }

    @MainActor
    func testRemoveNotifiesPlaybackOnlyAfterSuccessfulStoreMutation() async throws {
        let source = FolderSource(name: "Root", bookmark: Data([1]))
        let store = MemoryRoots([source])
        let access = BrowserAccess(source: source, listings: ["": []])
        var removed: [UUID] = []
        let model = FolderBrowserViewModel(store: store, access: access, onPlay: { _ in }, onRemoveSource: { removed.append($0) })
        model.refresh()
        await model.waitForCurrentLoad()
        await store.failRemoval()
        model.remove(source)
        await model.waitForSourceMutation()
        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(model.sources.map(\.id), [source.id])
        XCTAssertNotNil(model.errorMessage)
        await store.allowRemoval()
        model.remove(source)
        await model.waitForSourceMutation()
        XCTAssertEqual(removed, [source.id])
        XCTAssertTrue(model.sources.isEmpty)
        let forgotten = await access.forgottenIDs()
        XCTAssertEqual(forgotten, [source.id])
    }
}

private actor MemoryRoots: FolderSourceStoring {
    private var sources: [FolderSource]
    private var removalFails = false
    init(_ sources: [FolderSource]) { self.sources = sources }
    func load() -> [FolderSource] { sources }
    func upsert(_ source: FolderSource) -> [FolderSource] {
        if let index = sources.firstIndex(where: { $0.id == source.id }) { sources[index] = source }
        else { sources.append(source) }
        return sources
    }
    func updateExisting(_ source: FolderSource) -> [FolderSource] {
        if let index = sources.firstIndex(where: { $0.id == source.id }) { sources[index] = source }
        return sources
    }
    func remove(id: UUID) throws -> [FolderSource] {
        if removalFails { throw FolderSourceStoreError.writeFailed }
        sources.removeAll { $0.id == id }
        return sources
    }
    func failRemoval() { removalFails = true }
    func allowRemoval() { removalFails = false }
}

private actor BrowserAccess: FolderAccessing {
    private let source: FolderSource
    private let listings: [String: [FolderEntry]]
    private var prepared: [UUID] = []
    private var released: [UUID] = []
    private var forgotten: [UUID] = []
    private var heldPath: String?
    private var listingContinuation: CheckedContinuation<FolderListing, Error>?
    private var listingRequested: CheckedContinuation<Void, Never>?
    private var heldEntryID: UUID?
    private var preparationContinuation: CheckedContinuation<CachedAudioLease, Error>?
    private var preparationRequested: CheckedContinuation<Void, Never>?
    private var leaseRelease: CheckedContinuation<Void, Never>?
    init(source: FolderSource, listings: [String: [FolderEntry]]) { self.source = source; self.listings = listings }
    func makeSource(at url: URL) -> FolderSource { source }
    func list(source: FolderSource, relativePath: String) async throws -> FolderListing {
        if heldPath == relativePath {
            let result = try await withCheckedThrowingContinuation { continuation in
                listingContinuation = continuation
                listingRequested?.resume()
                listingRequested = nil
            }
            return result
        }
        return FolderListing(source: source, relativePath: relativePath, entries: listings[relativePath] ?? [])
    }
    func prepare(source: FolderSource, entry: FolderEntry, priority: FolderPreparationPriority) async throws -> CachedAudioLease {
        prepared.append(entry.id)
        if heldEntryID == entry.id {
            return try await withCheckedThrowingContinuation { continuation in
                preparationContinuation = continuation
                preparationRequested?.resume()
                preparationRequested = nil
            }
        }
        return CachedAudioLease(url: URL(fileURLWithPath: "/test-cache/\(entry.id.uuidString).mp3"), entryID: entry.id)
    }
    func release(_ lease: CachedAudioLease) {
        released.append(lease.entryID)
        leaseRelease?.resume()
        leaseRelease = nil
    }
    func forget(sourceID: UUID) { forgotten.append(sourceID) }
    func preparedIDs() -> [UUID] { prepared }
    func releasedIDs() -> [UUID] { released }
    func forgottenIDs() -> [UUID] { forgotten }
    func holdListing(at path: String) { heldPath = path }
    func waitForHeldListing(at path: String) async {
        if listingContinuation != nil { return }
        await withCheckedContinuation { listingRequested = $0 }
    }
    func completeHeldListing(at path: String) {
        listingContinuation?.resume(returning: FolderListing(source: source, relativePath: path, entries: listings[path] ?? []))
        listingContinuation = nil
        heldPath = nil
    }
    func holdPreparation(for id: UUID) { heldEntryID = id }
    func waitForHeldPreparation() async {
        if preparationContinuation != nil { return }
        await withCheckedContinuation { preparationRequested = $0 }
    }
    func completeHeldPreparation() {
        guard let id = heldEntryID else { return }
        preparationContinuation?.resume(returning: CachedAudioLease(url: URL(fileURLWithPath: "/test-cache/late.mp3"), entryID: id))
        preparationContinuation = nil
        heldEntryID = nil
    }
    func waitForLeaseRelease() async {
        if !released.isEmpty { return }
        await withCheckedContinuation { leaseRelease = $0 }
    }
}
