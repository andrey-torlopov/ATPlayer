import AVFoundation
import Foundation
import SwiftData
import UIKit

/// A separate simulator application built from the unmodified production services
/// and view model. Its bundle identifier and in-memory database isolate user data.
@main
@MainActor
final class PlaybackIntegrationApp: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Regression", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = PlaybackIntegrationScene.self
        return configuration
    }
}

@MainActor
final class PlaybackIntegrationScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var hasStarted = false

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard !hasStarted else { return }
        hasStarted = true
        Task {
            let success = await PlaybackIntegrationRegression().run()
            fflush(stdout)
            exit(success ? 0 : 1)
        }
    }
}

@MainActor
final class PlaybackIntegrationRegression {
    struct Failure: Error { let message: String }
    struct Result: Codable {
        let name: String
        let passed: Bool
        let assertions: Int
        let failure: String?
    }
    struct Report: Codable {
        let scope: String
        let passed: Int
        let total: Int
        let assertions: Int
        let results: [Result]
    }

    final class Fixture {
        let container: ModelContainer
        let model: ATPlayerViewModel
        let root: URL
        let first: [TrackItem]
        let second: [TrackItem]

        init() throws {
            for key in ["playbackMode", "playbackRepeatMode", "playbackShuffleEnabled", "lastPlayedSectionID"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
            container = try ModelContainer(
                for: PlaylistSection.self, TrackItem.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let storage = PlaylistStorageService(context: container.mainContext)
            let a = try storage.createSection(name: "Regression A")
            let b = try storage.createSection(name: "Regression B")
            var aTracks: [TrackItem] = []
            var bTracks: [TrackItem] = []
            for (section, count) in [(a, 3), (b, 2)] {
                for index in 0..<count {
                    let url = root.appendingPathComponent("\(section.order)-\(index).wav")
                    try Self.writeAudio(to: url)
                    let track = try storage.appendTrack(
                        title: "\(section.name) \(index)", artist: "Original test audio",
                        url: url, bookmark: url.bookmarkData(options: .minimalBookmark),
                        duration: 10, artwork: nil, to: section
                    )
                    if section.id == a.id { aTracks.append(track) } else { bTracks.append(track) }
                }
            }
            first = aTracks
            second = bTracks
            model = ATPlayerViewModel(context: container.mainContext)
        }

        static func writeAudio(to url: URL) throws {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 441000),
                  let samples = buffer.floatChannelData?[0] else {
                throw Failure(message: "Unable to create original PCM fixture")
            }
            buffer.frameLength = buffer.frameCapacity
            for frame in 0..<Int(buffer.frameLength) {
                samples[frame] = Float(sin(2 * .pi * 220 * Double(frame) / 44100)) * 0.002
            }
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }

        func cleanup() async throws {
            await model.performPlaybackCommand(.pause)
            model.playbackService.stop()
            model.activityService.endActivity()
            try FileManager.default.removeItem(at: root)
            for key in ["playbackMode", "playbackRepeatMode", "playbackShuffleEnabled", "lastPlayedSectionID"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    private var assertions = 0

    func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        assertions += 1
        guard condition() else { throw Failure(message: message) }
    }

    func until(_ message: String, condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw Failure(message: "Timed out: \(message)") }
            await Task.yield()
        }
        try expect(condition(), message)
    }

    func settle() async {
        // Drain queued MainActor tasks; no arbitrary time sleep is needed.
        for _ in 0..<100 { await Task.yield() }
    }

    func start(_ track: TrackItem, in fixture: Fixture) async throws {
        await fixture.model.play(track: track)
        try expect(fixture.model.selectedTrackID == track.id, "Requested track must be selected")
        try expect(fixture.model.playbackService.isPlaying, "Real AVAudioEngine must be playing")
        try expect(fixture.model.importError == nil, "Successful playback must not publish an error")
    }

    func setMode(_ mode: PlaybackMode, in fixture: Fixture) throws {
        for _ in 0..<4 {
            if fixture.model.playbackMode == mode { break }
            fixture.model.cyclePlaybackMode()
        }
        try expect(fixture.model.playbackMode == mode, "Requested mode must be reachable through the one button")
    }

    func run() async -> Bool {
        let tests: [(String, (Fixture) async throws -> Void)] = [
            ("normal EOF crosses playlist boundary", normalBoundary),
            ("normal library end stops", normalEnd),
            ("normal previous crosses back to preceding playlist", normalPrevious),
            ("playlist repeat wraps and previous stays scoped", playlistRepeat),
            ("repeat one restarts same track and permits manual next", repeatOne),
            ("shuffle is unique, reversible and stops after one pass", shuffle),
            ("switching exclusive modes preserves selection and position", modeTransitions),
            ("unavailable files are skipped within repeated playlist", missingFiles),
            ("all unavailable files exhaust finite fallback", allMissingFiles),
            ("restored files can resume after exhausted fallback", resumeAfterMissing),
            ("pause cancels scheduled EOF continuation", pauseAfterEOF),
            ("exclusive playback preference survives model recreation", preferences),
            ("legacy preferences migrate with deterministic priority", legacyPreferences)
        ]
        var results: [Result] = []
        // Production keeps its container for the application lifetime. Keep the
        // independent in-memory stores alive too: queued presentation callbacks
        // may outlive a fixture's local variable after its audio has stopped.
        var containers: [ModelContainer] = []
        for (name, test) in tests {
            let previousAssertions = assertions
            var fixture: Fixture?
            var failure: String?
            do {
                let value = try Fixture()
                containers.append(value.container)
                fixture = value
                try await test(value)
            } catch let error as Failure {
                failure = error.message
            } catch {
                let nsError = error as NSError
                failure = "Unexpected error domain=\(nsError.domain), code=\(nsError.code)"
            }
            if let fixture {
                do { try await fixture.cleanup() }
                catch { failure = failure ?? "Fixture cleanup failed" }
            }
            fixture = nil
            await settle()
            results.append(Result(name: name, passed: failure == nil, assertions: assertions - previousAssertions, failure: failure))
            print("\(failure == nil ? "PASS" : "FAIL"): \(name)\(failure.map { ": \($0)" } ?? "")")
            fflush(stdout)
        }
        let passed = results.filter(\.passed).count
        let report = Report(
            scope: "Real production ATPlayerViewModel, SwiftData, AVAudioEngine, NowPlayingService and ActivityService in an isolated simulator app. EOF triggered through production seek(to:duration).",
            passed: passed, total: results.count, assertions: assertions, results: results
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("integration-results.json")
            try data.write(to: url, options: .atomic)
            print("REPORT: Documents/integration-results.json")
        } catch {
            print("FAIL: unable to save integration report")
            return false
        }
        print("RESULT: passed / total = \(passed) / \(results.count); assertions = \(assertions)")
        return withExtendedLifetime(containers) { passed == results.count }
    }

    func normalBoundary(_ fixture: Fixture) async throws {
        try await start(fixture.first[2], in: fixture)
        fixture.model.seek(to: fixture.model.playbackService.duration)
        try await until("Normal EOF must advance into the next playlist") {
            fixture.model.selectedTrackID == fixture.second[0].id && fixture.model.playbackService.isPlaying
        }
    }

    func normalEnd(_ fixture: Fixture) async throws {
        try await start(fixture.second[1], in: fixture)
        fixture.model.seek(to: fixture.model.playbackService.duration)
        await settle()
        try expect(fixture.model.selectedTrackID == fixture.second[1].id, "Library end keeps last selection")
        try expect(!fixture.model.playbackService.isPlaying && !fixture.model.playbackService.isStarting, "Library end stops without a new audio start")
        try expect(!fixture.model.canPlayNext, "Next must be unavailable at library end")
    }

    func normalPrevious(_ fixture: Fixture) async throws {
        try await start(fixture.second[0], in: fixture)
        await fixture.model.performPlaybackCommand(.previous)
        try expect(fixture.model.selectedTrackID == fixture.first[2].id, "Normal previous crosses the playlist boundary")
        try expect(fixture.model.playbackService.isPlaying, "Normal previous starts the preceding track")
        await fixture.model.play(track: fixture.first[0])
        try expect(!fixture.model.canPlayPrevious, "Normal first track has no previous candidate")
        await fixture.model.performPlaybackCommand(.previous)
        try expect(fixture.model.selectedTrackID == fixture.first[0].id, "Previous at library start leaves selection unchanged")
    }

    func playlistRepeat(_ fixture: Fixture) async throws {
        try setMode(.repeatPlaylist, in: fixture)
        try await start(fixture.first[2], in: fixture)
        fixture.model.seek(to: fixture.model.playbackService.duration)
        try await until("Playlist EOF must wrap to its own first track") {
            fixture.model.selectedTrackID == fixture.first[0].id && fixture.model.playbackService.isPlaying
        }
        await fixture.model.performPlaybackCommand(.previous)
        try expect(fixture.model.selectedTrackID == fixture.first[2].id, "Previous from playlist start wraps to its own end")
        try expect(fixture.model.playbackService.isPlaying, "Wrapped previous starts audio")
    }

    func repeatOne(_ fixture: Fixture) async throws {
        try setMode(.repeatOne, in: fixture)
        try await start(fixture.first[1], in: fixture)
        fixture.model.seek(to: fixture.model.playbackService.duration)
        try await until("Repeat one must restart the same track from the beginning") {
            fixture.model.selectedTrackID == fixture.first[1].id
                && fixture.model.playbackService.isPlaying
                && fixture.model.playbackService.currentTime < 1
        }
        await fixture.model.performPlaybackCommand(.next)
        try expect(fixture.model.selectedTrackID == fixture.first[2].id, "Manual next ignores automatic repeat-one policy")
        try expect(fixture.model.playbackService.isPlaying, "Manual next starts the new track")
    }

    func shuffle(_ fixture: Fixture) async throws {
        try await start(fixture.first[0], in: fixture)
        try setMode(.shuffle, in: fixture)
        var visited = [fixture.first[0].id]
        for _ in 0..<2 {
            await fixture.model.performPlaybackCommand(.next)
            guard let selected = fixture.model.selectedTrackID else { throw Failure(message: "Shuffle lost selection") }
            try expect(!visited.contains(selected), "Shuffle cannot repeat before the playlist is exhausted")
            visited.append(selected)
            try expect(fixture.model.playbackService.isPlaying, "Every shuffled track must start real playback")
        }
        try expect(Set(visited) == Set(fixture.first.map(\.id)), "Shuffle visits exactly the current playlist")
        try expect(!fixture.model.canPlayNext, "Shuffle without repeat has a finite end")
        fixture.model.seek(to: fixture.model.playbackService.duration)
        await settle()
        try expect(!fixture.model.playbackService.isPlaying, "Shuffle EOF stops after a complete pass")
        await fixture.model.performPlaybackCommand(.previous)
        try expect(fixture.model.selectedTrackID == visited[1], "Previous returns to the previously played shuffled track")
    }

    func modeTransitions(_ fixture: Fixture) async throws {
        try await start(fixture.first[1], in: fixture)
        fixture.model.seek(to: 2)
        try await until("Seek must finish before testing mode transitions") {
            fixture.model.playbackService.isPlaying && fixture.model.playbackService.currentTime >= 2
        }
        for expected in [PlaybackMode.repeatPlaylist, .shuffle, .repeatOne, .off] {
            let position = fixture.model.playbackService.currentTime
            fixture.model.cyclePlaybackMode()
            try expect(fixture.model.playbackMode == expected, "One button cycles all four exclusive modes in order")
            try expect(fixture.model.selectedTrackID == fixture.first[1].id, "Changing mode cannot change the current track")
            try expect(fixture.model.playbackService.currentTime == position, "Changing mode cannot seek or restart the track")
            try expect(fixture.model.playbackService.isPlaying, "Changing mode keeps active playback running")
            await settle()
            try expect(fixture.model.playbackService.currentTime >= position, "Queued presentation updates cannot reset playback after a mode change")
        }
        await fixture.model.performPlaybackCommand(.pause)
        let pausedPosition = fixture.model.playbackService.currentTime
        for expected in [PlaybackMode.repeatPlaylist, .shuffle, .repeatOne, .off] {
            fixture.model.cyclePlaybackMode()
            await settle()
            try expect(fixture.model.playbackMode == expected, "Mode cycle remains available while paused")
            try expect(fixture.model.selectedTrackID == fixture.first[1].id, "Paused selection survives mode changes")
            try expect(fixture.model.playbackService.currentTime == pausedPosition, "Paused position survives mode changes")
            try expect(!fixture.model.playbackService.isPlaying && !fixture.model.playbackService.isStarting, "Changing mode cannot resume paused audio")
        }
    }

    func missingFiles(_ fixture: Fixture) async throws {
        try setMode(.repeatPlaylist, in: fixture)
        try await start(fixture.first[2], in: fixture)
        for track in fixture.first.prefix(2) {
            try FileManager.default.removeItem(atPath: track.filePath)
        }
        await fixture.model.performPlaybackCommand(.next)
        try expect(fixture.model.selectedTrackID == fixture.first[2].id, "Unavailable tracks may be skipped only inside the repeated playlist")
        try expect(fixture.model.playbackService.isPlaying, "The remaining accessible track restarts")
        try expect(fixture.model.importError == nil, "Successful fallback clears transient file errors")
    }

    func allMissingFiles(_ fixture: Fixture) async throws {
        try setMode(.repeatPlaylist, in: fixture)
        try await start(fixture.first[2], in: fixture)
        for track in fixture.first {
            try FileManager.default.removeItem(atPath: track.filePath)
        }
        let start = ContinuousClock.now
        await fixture.model.performPlaybackCommand(.next)
        try expect(ContinuousClock.now - start < .seconds(8), "All missing files must exhaust a bounded request")
        try expect(fixture.model.selectedTrackID == nil, "Failed repeated playlist resets selection instead of leaking into another playlist")
        try expect(!fixture.model.playbackService.isPlaying, "All missing files stop playback")
        try expect(fixture.model.importError != nil, "Exhausted fallback exposes an actionable error")
    }

    func resumeAfterMissing(_ fixture: Fixture) async throws {
        try setMode(.repeatPlaylist, in: fixture)
        try await start(fixture.first[2], in: fixture)
        for track in fixture.first {
            try FileManager.default.removeItem(atPath: track.filePath)
        }
        await fixture.model.performPlaybackCommand(.next)
        try expect(fixture.model.selectedTrackID == nil, "Missing playlist must first exhaust fallback")
        let restored = fixture.first[0]
        let url = URL(fileURLWithPath: restored.filePath)
        try Fixture.writeAudio(to: url)
        restored.bookmark = try url.bookmarkData(options: .minimalBookmark)
        try fixture.container.mainContext.save()
        fixture.model.reloadSections()
        await fixture.model.performPlaybackCommand(.play)
        try expect(fixture.model.selectedTrackID == restored.id, "Play after reset uses the restored first track")
        try expect(fixture.model.playbackService.isPlaying, "Playback queue remains usable after total fallback failure")
        try expect(fixture.model.importError == nil, "Successful resume clears exhausted-fallback error")
    }

    func pauseAfterEOF(_ fixture: Fixture) async throws {
        try setMode(.repeatPlaylist, in: fixture)
        try await start(fixture.first[2], in: fixture)
        fixture.model.seek(to: fixture.model.playbackService.duration)
        await fixture.model.performPlaybackCommand(.pause)
        await settle()
        try expect(fixture.model.selectedTrackID == fixture.first[2].id, "Pause must cancel queued EOF handoff before another selection")
        try expect(!fixture.model.playbackService.isPlaying && !fixture.model.playbackService.isStarting, "A paused EOF must not restart asynchronously")
    }

    func preferences(_ fixture: Fixture) async throws {
        for mode in [PlaybackMode.repeatPlaylist, .shuffle, .repeatOne, .off] {
            try setMode(mode, in: fixture)
            try expect(UserDefaults.standard.string(forKey: "playbackMode") == mode.rawValue, "Current exclusive mode is persisted under the new key")
            let restored = ATPlayerViewModel(context: fixture.container.mainContext)
            try expect(restored.playbackMode == mode, "Recreated model restores the exclusive mode")
            await restored.performPlaybackCommand(.pause)
            restored.playbackService.stop()
            restored.activityService.endActivity()
        }
    }

    func legacyPreferences(_ fixture: Fixture) async throws {
        let legacyCases: [(String?, Bool, PlaybackMode)] = [
            ("one", true, .repeatOne),
            ("one", false, .repeatOne),
            ("playlist", true, .shuffle),
            ("playlist", false, .repeatPlaylist),
            ("off", true, .shuffle),
            ("off", false, .off),
            (nil, false, .off),
            ("invalid-legacy-mode", false, .off)
        ]
        for (repeatValue, shuffleValue, expected) in legacyCases {
            UserDefaults.standard.removeObject(forKey: "playbackMode")
            if let repeatValue {
                UserDefaults.standard.set(repeatValue, forKey: "playbackRepeatMode")
            } else {
                UserDefaults.standard.removeObject(forKey: "playbackRepeatMode")
            }
            UserDefaults.standard.set(shuffleValue, forKey: "playbackShuffleEnabled")
            let restored = ATPlayerViewModel(context: fixture.container.mainContext)
            try expect(restored.playbackMode == expected, "Legacy migration must prioritize one, then shuffle, then playlist, then off")
            try expect(UserDefaults.standard.string(forKey: "playbackMode") == expected.rawValue, "Legacy migration stores a single new preference")
            await restored.performPlaybackCommand(.pause)
            restored.playbackService.stop()
            restored.activityService.endActivity()
        }
        UserDefaults.standard.set("invalid-new-mode", forKey: "playbackMode")
        UserDefaults.standard.set("playlist", forKey: "playbackRepeatMode")
        UserDefaults.standard.set(false, forKey: "playbackShuffleEnabled")
        let fallback = ATPlayerViewModel(context: fixture.container.mainContext)
        try expect(fallback.playbackMode == .repeatPlaylist, "An invalid new preference falls back to the valid legacy mode")
        try expect(UserDefaults.standard.string(forKey: "playbackMode") == PlaybackMode.repeatPlaylist.rawValue, "Invalid new preference is replaced with the migrated value")
        await fallback.performPlaybackCommand(.pause)
        fallback.playbackService.stop()
        fallback.activityService.endActivity()

        UserDefaults.standard.set(PlaybackMode.off.rawValue, forKey: "playbackMode")
        UserDefaults.standard.set("one", forKey: "playbackRepeatMode")
        UserDefaults.standard.set(true, forKey: "playbackShuffleEnabled")
        let restored = ATPlayerViewModel(context: fixture.container.mainContext)
        try expect(restored.playbackMode == .off, "An explicit new preference must win over retained legacy keys")
        await restored.performPlaybackCommand(.pause)
        restored.playbackService.stop()
        restored.activityService.endActivity()
    }
}
