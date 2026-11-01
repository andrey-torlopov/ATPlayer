import AVFoundation
import Foundation
import XCTest
@testable import PlayerInfrastructure

final class AudioPlaybackTests: XCTestCase {
    @MainActor
    func testRealEnginePauseResumeSeekAndFinish() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("audio.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 441_000))
        buffer.frameLength = buffer.frameCapacity
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for frame in 0..<Int(buffer.frameLength) {
            samples[frame] = Float(sin(2 * .pi * 220 * Double(frame) / 44_100)) * 0.002
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let audio = AudioPlaybackService()
        defer { audio.stop() }
        try await audio.loadAndPlay(url: url)
        XCTAssertTrue(audio.state.isPlaying)
        XCTAssertEqual(audio.state.duration, 10, accuracy: 0.01)
        audio.pauseByUser()
        XCTAssertFalse(audio.state.isPlaying)
        audio.seek(to: 2)
        XCTAssertEqual(audio.state.currentTime, 2, accuracy: 0.01)
        try await audio.play()?.value
        XCTAssertTrue(audio.state.isPlaying)
        var finished = false
        audio.onTrackFinished = { finished = true }
        audio.seek(to: audio.state.duration)
        XCTAssertTrue(finished)
        XCTAssertFalse(audio.state.isPlaying)
        audio.stop()
        XCTAssertEqual(audio.state.duration, 0)
    }
}
