import AVFoundation
import Combine
import Foundation
import SwiftData

@MainActor
enum LogicRegression {
    private struct BookmarkEnvelope: Codable {
        let file: Data
        let directory: Data?
    }

    static func run(_ harness: RegressionHarness) async {
        let originalLastSection = UserDefaults.standard.string(forKey: "lastPlayedSectionID")
        defer {
            if let originalLastSection {
                UserDefaults.standard.set(originalLastSection, forKey: "lastPlayedSectionID")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastPlayedSectionID")
            }
        }
        print("LOGIC_REGRESSION_BEGIN")
        do {
            try verifyModelFormatting(harness)
            try verifyStorage(harness)
            try verifyDuplicateExport(harness)
            try await verifyBookmarksAndDeletion(harness)
            try await verifyPreviousDirection(harness)
            try await verifyFolderImport(harness)
        } catch {
            harness.check(false, "Logic regression setup threw", detail: String(reflecting: error))
        }
        print("LOGIC_REGRESSION_END")
    }

    private static func context() throws -> ModelContext {
        let schema = Schema([PlaylistSection.self, TrackItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private static func append(
        _ storage: PlaylistStorageService,
        to section: PlaylistSection,
        title: String,
        url: URL,
        bookmark: Data? = nil,
        artwork: Data? = nil
    ) throws -> TrackItem {
        try storage.appendTrack(
            title: title,
            artist: "",
            url: url,
            bookmark: try bookmark ?? url.bookmarkData(options: .minimalBookmark),
            duration: 8,
            artwork: artwork,
            to: section
        )
    }

    private static func verifyModelFormatting(_ harness: RegressionHarness) throws {
        let item = TrackItem(
            title: "  ", artist: " Unknown Artist ",
            filePath: "/regression/First recording.wav", bookmark: Data(),
            duration: 61.9, order: 0
        )
        harness.check(item.displayName == "First recording", "Blank title falls back to filename")
        harness.check(item.displayArtist == nil, "Legacy Unknown Artist is absent")
        harness.check(item.displayTitle == "First recording", "Legacy placeholder omitted from title")
        harness.check(item.durationText == "1:01", "Finite duration truncates fractional seconds")
        item.artist = "  Actual performer  "
        item.title = "  Mixed case title  "
        harness.check(item.displayArtist == "Actual performer", "Actual artist metadata preserved")
        harness.check(item.displayTitle == "Actual performer - Mixed case title", "Metadata whitespace normalized")
        let invalidDurations: [Double] = [.nan, .infinity, -.infinity, -1, 0, Double(Int.max), .greatestFiniteMagnitude]
        for (index, value) in invalidDurations.enumerated() {
            item.duration = value
            harness.check(item.durationText == "--:--", "Unsafe duration rejected \(index)")
        }
        item.duration = 3_600
        harness.check(item.durationText == "60:00", "Hour duration remains complete minutes")
    }

    private static func verifyStorage(_ harness: RegressionHarness) throws {
        let context = try context()
        let storage = PlaylistStorageService(context: context)
        let a = try storage.createSection(name: "A")
        let b = try storage.createSection(name: "B")
        let c = try storage.createSection(name: "C")
        try storage.removeSection(b)
        let normalizedSections = try storage.fetchSections()
        harness.check(normalizedSections.map(\.order) == [0, 1], "Section delete normalizes order")
        let d = try storage.createSection(name: "D")
        harness.check(d.order == 2 && c.order == 1, "Section append uses next available order")
        let url = try harness.fixture(name: "logic-storage", seconds: 8)
        let first = try append(storage, to: a, title: "First", url: url)
        let second = try append(storage, to: a, title: "Second", url: url)
        let third = try append(storage, to: a, title: "Third", url: url)
        try storage.removeTrack(second)
        harness.check(storage.sortedTracks(in: a).map(\.id) == [first.id, third.id], "Track removal preserves remaining tracks")
        harness.check(storage.sortedTracks(in: a).map(\.order) == [0, 1], "Track delete normalizes order")
        let fourth = try append(storage, to: a, title: "Fourth", url: url)
        harness.check(fourth.order == 2, "Track append follows normalized order")
        try storage.removeSection(a)
        let remainingTracks = try context.fetch(FetchDescriptor<TrackItem>())
        harness.check(remainingTracks.isEmpty, "Section deletion cascades to its tracks")
    }

    private static func verifyDuplicateExport(_ harness: RegressionHarness) throws {
        let context = try context()
        let storage = PlaylistStorageService(context: context)
        let names = ["Mix", "Mix", "Mix (2)", "Mix (3)", "Mix"]
        let url = try harness.fixture(name: "logic-export", seconds: 8)
        for (index, name) in names.enumerated() {
            let section = try storage.createSection(name: name)
            _ = try append(storage, to: section, title: "Track \(index)", url: url)
        }
        let vm = ATPlayerViewModel(context: context)
        let object = try JSONSerialization.jsonObject(with: vm.exportPlaylistsJSON())
        guard let exported = object as? [String: [[String: String]]] else {
            harness.check(false, "Export remains JSON object of playlist arrays")
            return
        }
        harness.check(exported.count == names.count, "Duplicate playlist names preserve every playlist")
        let titles = exported.values.flatMap { $0.compactMap { $0["title"] } }.sorted()
        harness.check(titles == (0..<names.count).map { "Track \($0)" }, "Duplicate export preserves every track")
        harness.check(Set(exported.keys) == Set(["Mix", "Mix (2)", "Mix (3)", "Mix (4)", "Mix (5)"]), "Export suffixes avoid existing playlist names")
        harness.check(vm.sections.map(\.name) == names, "Export does not rename stored playlists")
    }

    private static func verifyBookmarksAndDeletion(_ harness: RegressionHarness) async throws {
        let context = try context()
        let storage = PlaylistStorageService(context: context)
        let section = try storage.createSection(name: "Bookmarks")
        let rawURL = try harness.fixture(name: "logic-legacy", seconds: 8)
        let artwork = Data([1, 2, 3])
        let raw = try append(storage, to: section, title: "Legacy mixed Case", url: rawURL, artwork: artwork)
        // Exercise production path repair using a valid bookmark and deliberately outdated stored path.
        raw.filePath = "/obsolete/location.wav"
        try context.save()
        let vm = ATPlayerViewModel(context: context)
        await vm.play(track: raw)
        harness.check(vm.selectedTrackID == raw.id && vm.playbackService.isPlaying, "Legacy raw bookmark plays")
        harness.check(raw.filePath == rawURL.path, "Bookmark resolution repairs stored file path")
        harness.check(vm.nowPlayingTitle == "Legacy mixed Case", "Now playing title preserves natural case")
        harness.check(vm.nowPlayingArtwork == artwork, "Active track has fixture artwork before deletion")
        vm.removeTrack(raw)
        harness.check(vm.selectedTrackID == nil, "Active track removal clears selected ID")
        harness.check(!vm.playbackService.isPlaying && vm.playbackService.duration == 0 && vm.playbackService.currentTime == 0, "Active track removal unloads audio and progress")
        harness.check(vm.nowPlayingArtwork == nil, "Active track removal clears artwork")
        harness.check(vm.allTracks.isEmpty, "Active track is removed from storage")

        let parent = harness.directory.appendingPathComponent("logic-envelope-\(UUID().uuidString)", isDirectory: true)
        let nested = parent.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let envelopeURL = nested.appendingPathComponent("Envelope.wav")
        try FileManager.default.copyItem(at: rawURL, to: envelopeURL)
        let envelope = BookmarkEnvelope(
            file: try envelopeURL.bookmarkData(options: .minimalBookmark),
            directory: try parent.bookmarkData(options: .minimalBookmark)
        )
        let track = try append(storage, to: section, title: "Folder recording", url: envelopeURL,
                               bookmark: JSONEncoder().encode(envelope), artwork: artwork)
        vm.reloadSections()
        await vm.play(track: track)
        harness.check(vm.selectedTrackID == track.id && vm.playbackService.isPlaying, "Folder envelope bookmark plays descendant")
        harness.check(vm.lastPlayedSectionID == section.id, "Playback records containing playlist")
        vm.removeSection(section)
        harness.check(vm.selectedTrackID == nil && !vm.playbackService.isPlaying, "Active playlist removal resets playback selection")
        harness.check(vm.playbackService.duration == 0 && vm.playbackService.currentTime == 0 && vm.nowPlayingArtwork == nil, "Active playlist removal clears timeline and artwork")
        harness.check(vm.lastPlayedSectionID == nil && UserDefaults.standard.string(forKey: "lastPlayedSectionID") == nil, "Active playlist removal clears persisted last playlist")
        let storedTracks = try context.fetch(FetchDescriptor<TrackItem>())
        harness.check(storedTracks.isEmpty, "Active playlist deletion cascades stored tracks")
        harness.check(vm.sections.count == 1 && vm.sections.first?.name == "My Music", "Empty library restores one default playlist")
    }

    private static func verifyPreviousDirection(_ harness: RegressionHarness) async throws {
        let context = try context()
        let storage = PlaylistStorageService(context: context)
        let section = try storage.createSection(name: "Navigation")
        let goodURL = try harness.fixture(name: "logic-navigation", seconds: 8)
        let emptyURL = try harness.fixture(name: "logic-empty", seconds: 0)
        let missingURL = try harness.fixture(name: "logic-missing", seconds: 1)
        let missingBookmark = try missingURL.bookmarkData(options: .minimalBookmark)
        let a = try append(storage, to: section, title: "A previous", url: goodURL)
        let b = try append(storage, to: section, title: "B empty", url: emptyURL)
        let c = try append(storage, to: section, title: "C missing", url: missingURL, bookmark: missingBookmark)
        let d = try append(storage, to: section, title: "D current", url: goodURL)
        try FileManager.default.removeItem(at: missingURL)
        let vm = ATPlayerViewModel(context: context)
        await vm.play(track: d)
        harness.check(vm.selectedTrackID == d.id && vm.playbackService.isPlaying, "Navigation starts at last valid track")
        harness.check(vm.canPlayPrevious && !vm.canPlayNext, "Navigation availability reflects last track")
        vm.playPrevious()
        let movedBackward = await harness.wait(until: { vm.selectedTrackID == a.id }, timeout: 8)
        harness.check(movedBackward && vm.playbackService.isPlaying, "Previous skips missing and empty files backward")
        harness.check(b.isCorrupted, "Empty audio file is marked corrupted")
        harness.check(!c.isCorrupted, "Missing file is not permanently marked corrupted")
        harness.check(!vm.canPlayPrevious && vm.canPlayNext, "Navigation availability reflects first track")
        vm.playNext()
        let movedForward = await harness.wait(until: { vm.selectedTrackID == d.id }, timeout: 8)
        harness.check(movedForward && vm.playbackService.isPlaying, "Next skips invalid files forward")
        vm.removeTrack(d)
        await vm.play(track: b)
        harness.check(vm.selectedTrackID == nil && !vm.playbackService.isPlaying && vm.playbackService.duration == 0, "Exhausted invalid candidates leave unloaded state")
        harness.check(vm.importError != nil, "Exhausted invalid candidates expose recoverable error")
        vm.playbackService.stop()
    }

    private static func verifyFolderImport(_ harness: RegressionHarness) async throws {
        let context = try context()
        let vm = ATPlayerViewModel(context: context)
        guard let section = vm.sections.first else {
            harness.check(false, "Folder import has default target")
            return
        }
        let source = try harness.fixture(name: "logic-import-source", seconds: 8)
        let parent = harness.directory.appendingPathComponent("logic-import-\(UUID().uuidString)", isDirectory: true)
        let nested = parent.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: parent.appendingPathComponent("First recording.wav"))
        try FileManager.default.copyItem(at: source, to: nested.appendingPathComponent("Second recording.WAV"))
        try Data("not audio".utf8).write(to: parent.appendingPathComponent("notes.txt"))
        vm.requestImport(to: section)
        vm.importFiles(.success([parent]))
        harness.check(vm.isImporting, "Import publishes in-progress state immediately")
        let imported = await harness.wait(until: { !vm.isImporting }, timeout: 12)
        harness.check(imported && vm.allTracks.count == 2, "Folder import includes supported descendants only")
        let tracks = vm.allTracks
        harness.check(tracks.map(\.displayName) == ["First recording", "Second recording"], "Import uses filenames without fabricated metadata")
        harness.check(tracks.allSatisfy { $0.artist.isEmpty && $0.displayArtist == nil }, "Missing artist metadata remains absent")
        let envelopesValid = tracks.allSatisfy { track in
            guard let envelope = try? JSONDecoder().decode(BookmarkEnvelope.self, from: track.bookmark) else { return false }
            return envelope.directory != nil && !envelope.file.isEmpty
        }
        harness.check(envelopesValid, "Every imported descendant persists directory access bookmark")
        if let nestedTrack = tracks.last {
            await vm.play(track: nestedTrack)
            harness.check(vm.selectedTrackID == nestedTrack.id && vm.playbackService.isPlaying, "Imported nested file plays after import scope closes")
            vm.playbackService.stop()
        }
        let count = vm.allTracks.count
        vm.requestImport(to: section)
        vm.importFiles(.success([parent]))
        vm.cancelImport()
        let cancelled = await harness.wait(until: { !vm.isImporting }, timeout: 4)
        harness.check(cancelled && vm.allTracks.count == count, "Cancelled import adds no files and resets progress")
        vm.importError = nil
        vm.importFiles(.failure(CocoaError(.userCancelled)))
        harness.check(vm.importError == nil, "Dismissed importer does not show an error")
    }
}
