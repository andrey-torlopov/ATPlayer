import AVFoundation
import Foundation
import PlaybackDomain
import XCTest
@testable import PlayerInfrastructure

final class RadioPlaybackTests: XCTestCase {
    @MainActor
    func testPreparingAndCancellingDoesNotReplaceActiveTrack() async throws {
        let fixture = try makeAudio(duration: 10)
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        let audio = AudioPlaybackService()
        defer { audio.stop() }
        audio.applyRadioSettings(RadioSettings(effectIntensity: 0))
        try await audio.loadAndPlay(url: fixture)
        let initialDuration = audio.state.duration
        var released: [AudioPreparedTrack] = []
        audio.onTrackReleased = { released.append($0) }
        let handle = try await audio.prepareTrack(url: fixture, requestID: UUID())
        XCTAssertTrue(audio.state.isPlaying)
        XCTAssertEqual(audio.state.duration, initialDuration)
        audio.cancelPreparedTrack(handle)
        audio.cancelPreparedTrack(handle)
        XCTAssertEqual(released, [handle])
        XCTAssertTrue(audio.state.isPlaying)
        XCTAssertThrowsError(try audio.scheduleReplacement(handle, atEnd: false))
    }

    @MainActor
    func testPauseCancelsPlannedEOFAndPreservesCommittedFile() async throws {
        let fixture = try makeAudio(duration: 10)
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        let audio = AudioPlaybackService()
        defer { audio.stop() }
        audio.applyRadioSettings(RadioSettings(effectIntensity: 10))
        try await audio.loadAndPlay(url: fixture)
        let handle = try await audio.prepareTrack(url: fixture, requestID: UUID())
        var committed = false
        var released = 0
        audio.onTrackStarted = { _ in committed = true }
        audio.onTrackReleased = { _ in released += 1 }
        try audio.scheduleReplacement(handle, atEnd: true)
        audio.pauseByUser()
        XCTAssertFalse(audio.state.isPlaying)
        XCTAssertFalse(audio.state.advancesTrackTime)
        XCTAssertFalse(committed)
        XCTAssertEqual(released, 1)
        XCTAssertEqual(audio.state.duration, 10, accuracy: 0.001)
        try await audio.play()?.value
        XCTAssertTrue(audio.state.isPlaying)
        XCTAssertEqual(audio.state.duration, 10, accuracy: 0.001)
    }

    @MainActor
    func testManualReplacementCommitsOnceAndKeepsPauseAvailable() async throws {
        let fixture = try makeAudio(duration: 5)
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        let audio = AudioPlaybackService()
        defer { audio.stop() }
        audio.applyRadioSettings(RadioSettings(effectIntensity: 0))
        try await audio.loadAndPlay(url: fixture)
        let handle = try await audio.prepareTrack(url: fixture, requestID: UUID())
        let began = expectation(description: "B reached the audible output timeline")
        began.assertForOverFulfill = true
        var commits: [AudioPreparedTrack] = []
        audio.onTrackStarted = { committed in commits.append(committed); began.fulfill() }
        try audio.scheduleReplacement(handle, atEnd: false)
        XCTAssertTrue(audio.state.isPlaying)
        await fulfillment(of: [began], timeout: 5)
        XCTAssertEqual(commits, [handle])
        XCTAssertLessThan(audio.state.currentTime, 0.5)
        audio.pauseByUser()
        XCTAssertFalse(audio.state.isPlaying)
        XCTAssertEqual(commits, [handle])
    }

    @MainActor
    func testAutomaticReplacementOwnsOutgoingEOFWithoutDoubleAdvance() async throws {
        let first = try makeAudio(duration: 0.4)
        let second = try makeAudio(duration: 3)
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }
        let audio = AudioPlaybackService()
        defer { audio.stop() }
        audio.applyRadioSettings(RadioSettings(effectIntensity: 0))
        try await audio.loadAndPlay(url: first)
        let handle = try await audio.prepareTrack(url: second, requestID: UUID())
        let began = expectation(description: "Automatic B committed")
        began.assertForOverFulfill = true
        var completedTracks = 0
        audio.onTrackFinished = { completedTracks += 1 }
        audio.onTrackStarted = { committed in
            XCTAssertEqual(committed, handle)
            began.fulfill()
        }
        try audio.scheduleReplacement(handle, atEnd: true)
        XCTAssertLessThan(audio.state.currentTime, audio.state.duration,
                          "Planning B must not jump A to EOF because of an uninitialized render epoch")
        await fulfillment(of: [began], timeout: 5)
        XCTAssertEqual(completedTracks, 0, "A's EOF must not also advance the queue")
        XCTAssertEqual(audio.state.duration, 3, accuracy: 0.001)
        XCTAssertTrue(audio.state.isPlaying)
        XCTAssertLessThan(audio.state.currentTime, 0.5)
    }

    @MainActor
    func testChangingNoiseAfterBAudibleBeforePresentationTickDoesNotRestartB() async throws {
        let fixture = try makeAudio(duration: 5)
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        let engine = AVAudioEngine()
        let firstNode = AVAudioPlayerNode()
        // Deliberately hold presentation updates; the audio clock still runs normally.
        let audio = AudioPlaybackService(engine: engine, playerNode: firstNode,
                                         notificationCenter: NotificationCenter(), progressUpdateInterval: 10)
        defer { audio.stop() }
        audio.applyRadioSettings(RadioSettings(effectIntensity: 0))
        try await audio.loadAndPlay(url: fixture)
        let secondNode = try XCTUnwrap(engine.attachedNodes.compactMap { $0 as? AVAudioPlayerNode }
            .first { $0 !== firstNode })
        let began = expectation(description: "B passed the output latency before UI commit")
        began.assertForOverFulfill = true
        let format = secondNode.outputFormat(forBus: 0)
        let probe = AudioOnsetProbe(
            frames: Int((secondNode.outputPresentationLatency + 0.05) * format.sampleRate), expectation: began)
        secondNode.installTap(onBus: 0, bufferSize: 256, format: format) { buffer, _ in probe.consume(buffer) }
        defer { secondNode.removeTap(onBus: 0) }
        let handle = try await audio.prepareTrack(url: fixture, requestID: UUID())
        var commits: [AudioPreparedTrack] = []
        audio.onTrackStarted = { commits.append($0) }
        try audio.scheduleReplacement(handle, atEnd: false)
        await fulfillment(of: [began], timeout: 5)
        XCTAssertTrue(commits.isEmpty, "This test must exercise the gap before the presentation tick")
        let beforeTime = try XCTUnwrap(secondNode.lastRenderTime)
        let before = try XCTUnwrap(secondNode.playerTime(forNodeTime: beforeTime)).sampleTime
        XCTAssertGreaterThan(before, 0)
        audio.applyRadioSettings(RadioSettings(effectIntensity: 10))
        let afterTime = try XCTUnwrap(secondNode.lastRenderTime)
        let after = try XCTUnwrap(secondNode.playerTime(forNodeTime: afterTime)).sampleTime
        XCTAssertEqual(commits, [handle], "The already audible B must commit exactly once")
        XCTAssertGreaterThanOrEqual(after, before, "Changing noise intensity must not rewind B")
        XCTAssertGreaterThan(audio.state.currentTime, 0)
    }

    private func makeAudio(duration: Double) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("radio-source.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(duration * 44_100)))
        buffer.frameLength = buffer.frameCapacity
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for frame in 0..<Int(buffer.frameLength) {
            samples[frame] = Float(sin(2 * .pi * 220 * Double(frame) / 44_100)) * 0.05
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}

/// All mutable fields are confined to this single test tap's serial render calls.
/// Only XCTest's thread-safe expectation crosses back to the test executor.
private final class AudioOnsetProbe: @unchecked Sendable {
    private let requiredFrames: Int
    private let expectation: XCTestExpectation
    private var nonSilentFrames = 0
    private var completed = false

    init(frames: Int, expectation: XCTestExpectation) {
        requiredFrames = max(1, frames)
        self.expectation = expectation
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        guard !completed, let samples = buffer.floatChannelData?[0] else { return }
        for frame in 0..<Int(buffer.frameLength) {
            if abs(samples[frame]) > 0.00001 { nonSilentFrames += 1 }
        }
        if nonSilentFrames >= requiredFrames {
            completed = true
            expectation.fulfill()
        }
    }
}
