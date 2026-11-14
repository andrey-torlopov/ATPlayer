import AVFoundation
import Combine
import Foundation
import XCTest
@testable import PlayerInfrastructure

@MainActor
final class AudioInterruptionTests: XCTestCase {
    private let eventTimeout: TimeInterval = 3

    func testExplicitResumeDoesNotRequireInterruptionEndedNotification() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try await fixture.start()
        fixture.interrupt(.began)
        fixture.audio.seek(to: 3)

        let resume = try XCTUnwrap(fixture.audio.play())
        XCTAssertTrue(fixture.audio.state.isStarting)
        try await resume.value

        XCTAssertTrue(fixture.audio.state.isPlaying)
        XCTAssertTrue(fixture.engine.isRunning)
        XCTAssertTrue(fixture.node.isPlaying)
        XCTAssertEqual(fixture.audio.state.currentTime, 3, accuracy: 0.1)
    }

    func testRealInterruptionCancelsPendingResumeImmediately() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try await fixture.start()
        fixture.audio.pauseByUser()
        let resume = try XCTUnwrap(fixture.audio.play())

        fixture.interrupt(.began)

        XCTAssertFalse(fixture.audio.state.isPlaying)
        XCTAssertFalse(fixture.audio.state.isStarting)
        do {
            try await resume.value
            XCTFail("An actual interruption must cancel pending activation.")
        } catch is CancellationError {
            // Expected: this is a new interruption, not a delayed suspension.
        }
        fixture.interrupt(.ended)
        try await fixture.audio.play()?.value
        XCTAssertTrue(fixture.audio.state.isPlaying)
    }

    func testRepeatedInterruptionBeganPreservesAutomaticResumeIntent() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try await fixture.start()
        fixture.interrupt(.began)
        fixture.interrupt(.began)
        XCTAssertFalse(fixture.audio.state.isPlaying)
        let resumed = expectation(description: "Interruption resumes audio once permitted")
        let observation = fixture.audio.state.$isPlaying.filter { $0 }.prefix(1)
            .sink { _ in resumed.fulfill() }
        defer { observation.cancel() }

        fixture.interrupt(.ended, shouldResume: true)
        await fulfillment(of: [resumed], timeout: eventTimeout)

        XCTAssertTrue(fixture.audio.state.isPlaying)
    }

    func testUserPauseDuringInterruptionCancelsAutomaticResume() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try await fixture.start()
        fixture.interrupt(.began)
        fixture.audio.pauseByUser()

        fixture.interrupt(.ended, shouldResume: true)

        XCTAssertFalse(fixture.audio.state.isPlaying)
        XCTAssertFalse(fixture.audio.state.isStarting, "No automatic activation may be scheduled after user Pause.")
        try await fixture.audio.play()?.value
        XCTAssertTrue(fixture.audio.state.isPlaying)
    }

    func testInterruptionWithoutResumePermissionStaysPaused() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try await fixture.start()
        fixture.interrupt(.began)
        fixture.interrupt(.ended)

        XCTAssertFalse(fixture.audio.state.isPlaying)
        XCTAssertFalse(fixture.audio.state.isStarting)
        XCTAssertEqual(fixture.audio.state.duration, 10, accuracy: 0.01)
    }

    func testStoppedEngineIsReconciledAndExplicitPlayRemainsUsable() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try await fixture.start()
        var finished = false
        fixture.audio.onTrackFinished = { finished = true }

        // The isolated notification center deliberately withholds a system event.
        fixture.engine.stop()
        XCTAssertTrue(fixture.audio.state.isPlaying)
        fixture.audio.reconcilePlaybackState()

        XCTAssertFalse(fixture.audio.state.isPlaying)
        XCTAssertFalse(finished, "A stopped engine is not the end of a track.")
        XCTAssertEqual(fixture.audio.state.duration, 10, accuracy: 0.01)
        try await fixture.audio.play()?.value
        XCTAssertTrue(fixture.audio.state.isPlaying)
        XCTAssertTrue(fixture.engine.isRunning)
        XCTAssertFalse(finished)
    }

    func testReconciliationBeforeInterruptionPreservesResumeIntent() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try await fixture.start()
        fixture.engine.stop()
        fixture.audio.reconcilePlaybackState()
        fixture.interrupt(.began)
        let resumed = expectation(description: "Interruption retains intent detected before notification")
        let observation = fixture.audio.state.$isPlaying.filter { $0 }.prefix(1)
            .sink { _ in resumed.fulfill() }
        defer { observation.cancel() }

        fixture.interrupt(.ended, shouldResume: true)
        await fulfillment(of: [resumed], timeout: eventTimeout)

        XCTAssertTrue(fixture.audio.state.isPlaying)
    }

    func testReconciliationBeforeConfigurationChangePreservesResumeIntent() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try await fixture.start()
        fixture.engine.stop()
        fixture.audio.reconcilePlaybackState()
        let resumed = expectation(description: "Configuration change recovers stopped output")
        let observation = fixture.audio.state.$isPlaying.filter { $0 }.prefix(1)
            .sink { _ in resumed.fulfill() }
        defer { observation.cancel() }

        fixture.center.post(name: .AVAudioEngineConfigurationChange, object: fixture.engine)
        await fulfillment(of: [resumed], timeout: eventTimeout)

        XCTAssertTrue(fixture.audio.state.isPlaying)
    }

    func testUserPauseAfterReconciliationCancelsConfigurationRecovery() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try await fixture.start()
        fixture.engine.stop()
        fixture.audio.reconcilePlaybackState()
        fixture.audio.pauseByUser()

        fixture.center.post(name: .AVAudioEngineConfigurationChange, object: fixture.engine)
        fixture.interrupt(.began)
        fixture.interrupt(.ended, shouldResume: true)

        XCTAssertFalse(fixture.audio.state.isPlaying)
        XCTAssertFalse(fixture.audio.state.isStarting)
    }

    func testNaturalEndOfFileCompletesExactlyOnceWithStateMonitoring() async throws {
        let fixture = try Fixture(frameCount: 22_050)
        defer { fixture.cleanup() }
        let finished = expectation(description: "Actual rendered EOF completes the track")
        finished.assertForOverFulfill = true
        var finishCount = 0
        fixture.audio.onTrackFinished = { finishCount += 1; finished.fulfill() }

        try await fixture.start()
        await fulfillment(of: [finished], timeout: eventTimeout)

        fixture.audio.reconcilePlaybackState()
        XCTAssertEqual(finishCount, 1)
        XCTAssertFalse(fixture.audio.state.isPlaying)
        XCTAssertEqual(fixture.audio.state.currentTime, fixture.audio.state.duration, accuracy: 0.01)
    }

    @MainActor
    private struct Fixture {
        let root: URL
        let url: URL
        let engine: AVAudioEngine
        let node: AVAudioPlayerNode
        let center: NotificationCenter
        let audio: AudioPlaybackService

        init(frameCount: AVAudioFrameCount = 441_000) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            url = root.appendingPathComponent("interruption.wav")
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
            buffer.frameLength = buffer.frameCapacity
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            for frame in 0..<Int(buffer.frameLength) {
                samples[frame] = Float(sin(2 * .pi * 220 * Double(frame) / 44_100)) * 0.002
            }
            do {
                let file = try AVAudioFile(forWriting: url, settings: format.settings)
                try file.write(from: buffer)
            }
            engine = AVAudioEngine()
            node = AVAudioPlayerNode()
            center = NotificationCenter()
            audio = AudioPlaybackService(engine: engine, playerNode: node, notificationCenter: center)
        }

        func start() async throws { try await audio.loadAndPlay(url: url) }

        func interrupt(_ type: AVAudioSession.InterruptionType, shouldResume: Bool = false) {
            center.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: [
                AVAudioSessionInterruptionTypeKey: type.rawValue,
                AVAudioSessionInterruptionOptionKey: shouldResume ? AVAudioSession.InterruptionOptions.shouldResume.rawValue : 0
            ])
        }

        func cleanup() {
            audio.stop()
            try? FileManager.default.removeItem(at: root)
        }
    }
}
