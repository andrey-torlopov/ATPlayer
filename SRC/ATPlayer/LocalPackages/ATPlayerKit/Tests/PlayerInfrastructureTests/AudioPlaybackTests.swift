import AVFoundation
import Foundation
import FolderDomain
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

    @MainActor
    func testFolderCachePlaysAfterSourceDisappearsAndPinsUntilEngineStops() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        let cache = root.appendingPathComponent("Cache", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = sources.appendingPathComponent("original.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 441_000))
        buffer.frameLength = buffer.frameCapacity
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for frame in 0..<Int(buffer.frameLength) {
            samples[frame] = Float(sin(2 * .pi * 220 * Double(frame) / 44_100)) * 0.002
        }
        do {
            let file = try AVAudioFile(forWriting: sourceURL, settings: format.settings)
            try file.write(from: buffer)
        }
        let folders = FolderAccessService(cacheDirectory: cache, maximumCacheBytes: 1024)
        let source = try await folders.makeSource(at: sources)
        let listing = try await folders.list(source: source, relativePath: "")
        let entry = try XCTUnwrap(listing.entries.first)
        let lease = try await folders.prepare(source: source, entry: entry, priority: .playback)
        try FileManager.default.removeItem(at: sourceURL)
        let audio = AudioPlaybackService()
        do {
            try await audio.loadAndPlay(url: lease.url)
            XCTAssertTrue(audio.state.isPlaying, "Real AVAudioEngine must start from the complete cache after the source disappears.")
            XCTAssertEqual(audio.state.duration, 10, accuracy: 0.01)
            await folders.forget(sourceID: source.id)
            XCTAssertTrue(FileManager.default.fileExists(atPath: lease.url.path), "The cache must retain a lease even after its root is forgotten.")
            audio.pauseByUser()
            audio.seek(to: 3)
            try await audio.play()?.value
            XCTAssertTrue(audio.state.isPlaying, "Seek/resume must remain independent of provider availability.")
            audio.stop()
            await folders.release(lease)
            XCTAssertFalse(FileManager.default.fileExists(atPath: lease.url.path), "Cleanup follows engine stop and final lease release.")
        } catch {
            audio.stop()
            await folders.release(lease)
            throw error
        }
    }
}
