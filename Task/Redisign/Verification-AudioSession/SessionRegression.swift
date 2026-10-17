import AVFoundation
import Foundation
import ObjectiveC
import SwiftData

// Only the temporary regression executable installs these interceptors. The
// original Apple methods still execute, on the thread chosen by production code.
nonisolated final class ActivationGate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var entered = false
    let fails: Bool

    init(fails: Bool = false) { self.fails = fails }

    var hasEntered: Bool {
        lock.lock()
        defer { lock.unlock() }
        return entered
    }

    func block() {
        lock.lock()
        entered = true
        lock.unlock()
        // A broken test must not hang the simulator indefinitely.
        precondition(semaphore.wait(timeout: .now() + 10) == .success, "Activation gate was not released")
    }

    func release() { semaphore.signal() }
}

nonisolated final class SessionProbe: @unchecked Sendable {
    static let shared = SessionProbe()
    private let lock = NSLock()
    private var categoryCalls = 0
    private var activationCalls = 0
    private var mainThreadCalls = 0
    private var nextGate: ActivationGate?

    var counts: (category: Int, activation: Int, main: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (categoryCalls, activationCalls, mainThreadCalls)
    }

    func arm(fails: Bool = false) -> ActivationGate {
        lock.lock()
        defer { lock.unlock() }
        precondition(nextGate == nil)
        let gate = ActivationGate(fails: fails)
        nextGate = gate
        return gate
    }

    func record(category: Bool) throws {
        lock.lock()
        if category { categoryCalls += 1 } else { activationCalls += 1 }
        if Thread.isMainThread { mainThreadCalls += 1 }
        let gate = category ? nil : nextGate
        if !category { nextGate = nil }
        lock.unlock()
        gate?.block()
        if gate?.fails == true { throw NSError(domain: "ATPlayer.Regression.Session", code: 42) }
    }
}

extension AVAudioSession {
    @objc nonisolated func regression_setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws {
        try SessionProbe.shared.record(category: true)
        try regression_setCategory(category, mode: mode, options: options)
    }

    @objc nonisolated func regression_setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        try SessionProbe.shared.record(category: false)
        try regression_setActive(active, options: options)
    }
}

@MainActor
enum SessionRegression {
    private static func exchange(_ original: String, _ replacement: Selector) throws {
        guard let first = class_getInstanceMethod(AVAudioSession.self, NSSelectorFromString(original)),
              let second = class_getInstanceMethod(AVAudioSession.self, replacement) else {
            throw RegressionHarness.Failure.invalidFixtureFormat
        }
        method_exchangeImplementations(first, second)
    }

    static func run(_ h: RegressionHarness) async throws {
        // Force one real category change, entirely off the UI thread.
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setActive(false)
                    try session.setCategory(.ambient, mode: .default, options: [])
                    c.resume()
                } catch { c.resume(throwing: error) }
            }
        }
        try exchange("setCategory:mode:options:error:", #selector(AVAudioSession.regression_setCategory(_:mode:options:)))
        try exchange("setActive:withOptions:error:", #selector(AVAudioSession.regression_setActive(_:options:)))
        defer {
            try? exchange("setActive:withOptions:error:", #selector(AVAudioSession.regression_setActive(_:options:)))
            try? exchange("setCategory:mode:options:error:", #selector(AVAudioSession.regression_setCategory(_:mode:options:)))
        }

        let service = AudioPlaybackService()
        let tone = try h.fixture(name: "session-first", seconds: 5)
        let replacement = try h.fixture(name: "session-replacement", seconds: 8)
        var finished = 0
        service.onTrackFinished = { finished += 1 }

        // A held system call gives deterministic evidence that MainActor remains
        // available and stop invalidates a request already in the audio worker.
        let gate1 = SessionProbe.shared.arm()
        let stoppedLoad = Task { try await service.loadAndPlay(url: tone) }
        let entered = await h.wait { gate1.hasEntered }
        h.check(entered && service.isStarting && !service.isPlaying, "session.mainActorAvailableDuringActivation")
        service.stop()
        gate1.release()
        let stoppedLoadCancelled = await wasCancelled(stoppedLoad)
        h.check(stoppedLoadCancelled, "session.stop.cancelsInflightLoad")
        h.check(!service.isPlaying && !service.isStarting && service.duration == 0 && service.playbackError == nil && finished == 0, "session.stop.noLatePlaybackOrError")

        let gate2 = SessionProbe.shared.arm()
        let pausedLoad = Task { try await service.loadAndPlay(url: tone) }
        _ = await h.wait { gate2.hasEntered }
        service.pause()
        gate2.release()
        let pausedLoadCancelled = await wasCancelled(pausedLoad)
        h.check(pausedLoadCancelled, "session.pause.cancelsInflightLoad")
        h.check(!service.isPlaying && !service.isStarting && service.duration == 5, "session.pause.retainsFile")
        service.play()
        h.check(service.isStarting, "session.resume.publishesPendingSynchronously")
        let count = SessionProbe.shared.counts.activation
        service.play()
        let resumed = await h.wait { service.isPlaying }
        h.check(resumed && SessionProbe.shared.counts.activation == count + 1, "session.resume.duplicatePlayIgnored")
        service.pause()

        let gate3 = SessionProbe.shared.arm()
        let seekLoad = Task { try await service.loadAndPlay(url: tone) }
        _ = await h.wait { gate3.hasEntered }
        service.seek(to: 1)
        service.seek(to: 2)
        service.seek(to: 3)
        gate3.release()
        let seekLoadCancelled = await wasCancelled(seekLoad)
        h.check(seekLoadCancelled, "session.seek.supersedesInflightLoad")
        let sought = await h.wait { service.isPlaying }
        h.check(sought && service.currentTime >= 3 && service.currentTime < 3.3 && service.playbackError == nil, "session.seek.lastPositionWins")
        service.stop()

        let gate4 = SessionProbe.shared.arm(fails: true)
        let olderLoad = Task { try await service.loadAndPlay(url: tone) }
        _ = await h.wait { gate4.hasEntered }
        let newerLoad = Task { try await service.loadAndPlay(url: replacement) }
        _ = await h.wait { service.duration == 8 && service.isStarting }
        gate4.release()
        let olderLoadCancelled = await wasCancelled(olderLoad)
        h.check(olderLoadCancelled, "session.replacement.staleFailureBecomesCancellation")
        try await newerLoad.value
        h.check(service.isPlaying && service.duration == 8 && service.playbackError == nil, "session.replacement.staleFailureCannotStopNewTrack")
        service.stop()

        let gate5 = SessionProbe.shared.arm()
        let cancelledLoad = Task { try await service.loadAndPlay(url: tone) }
        _ = await h.wait { gate5.hasEntered }
        cancelledLoad.cancel()
        gate5.release()
        let cancelledLoadCancelled = await wasCancelled(cancelledLoad)
        h.check(cancelledLoadCancelled, "session.taskCancellation.propagatesToStart")
        h.check(!service.isPlaying && !service.isStarting && service.duration == 0 && service.playbackError == nil, "session.taskCancellation.noLatePlayback")

        // Exercise the production VM across its new suspension point too.
        let schema = Schema([PlaylistSection.self, TrackItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let storage = PlaylistStorageService(context: context)
        let section = try storage.ensureDefaultSection()
        let first = try storage.appendTrack(title: "First", artist: "", url: tone, bookmark: tone.bookmarkData(options: .minimalBookmark), duration: 5, artwork: nil, to: section)
        let second = try storage.appendTrack(title: "Second", artist: "", url: replacement, bookmark: replacement.bookmarkData(options: .minimalBookmark), duration: 8, artwork: nil, to: section)
        let vm = ATPlayerViewModel(context: context)
        let gate6 = SessionProbe.shared.arm(fails: true)
        let olderVM = Task { await vm.play(track: first) }
        _ = await h.wait { gate6.hasEntered }
        let newerVM = Task { await vm.play(track: second) }
        _ = await h.wait { vm.selectedTrackID == second.id && vm.playbackService.isStarting }
        gate6.release()
        await olderVM.value
        await newerVM.value
        h.check(vm.selectedTrackID == second.id && vm.nowPlayingTitle == "Second" && vm.playbackService.isPlaying && vm.importError == nil, "session.VM.replacementOwnsSelectionAndErrors")
        vm.playbackService.pause()

        let gate7 = SessionProbe.shared.arm()
        vm.togglePlayback()
        _ = await h.wait { gate7.hasEntered }
        vm.togglePlayback()
        h.check(!vm.playbackService.isStarting && !vm.playbackService.isPlaying, "session.VM.togglePausesPendingResume")
        gate7.release()
        // A fresh load is also a barrier after the cancelled worker operation.
        try await service.loadAndPlay(url: tone)
        h.check(!vm.playbackService.isPlaying && vm.importError == nil, "session.VM.cancelledResumeStaysPaused")
        service.stop()
        vm.playbackService.stop()
        let counts = SessionProbe.shared.counts
        h.check(counts.category == 1, "session.matchingCategoryNotReconfigured", detail: "categoryCalls=\(counts.category)")
        h.check(counts.activation > 0 && counts.main == 0, "session.systemCallsRunOffMainThread", detail: "activationCalls=\(counts.activation), mainThreadCalls=\(counts.main)")
    }

    private static func wasCancelled(_ task: Task<Void, Error>) async -> Bool {
        do { try await task.value; return false }
        catch is CancellationError { return true }
        catch { return false }
    }
}
