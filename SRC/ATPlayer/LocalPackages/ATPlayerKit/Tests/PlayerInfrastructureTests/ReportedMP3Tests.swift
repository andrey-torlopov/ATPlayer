import AVFoundation
import Combine
import CryptoKit
import FolderDomain
import Foundation
import XCTest
@testable import PlayerInfrastructure

/// The runner stages the optional reproduction under its original name; no renamed fixture is accepted.
enum ReportedMP3Fixture {
    static let fileName = "Airstream_-_Medianoche_Aftersun_Mix_Remastered_(SkySound.cc).mp3"
    static let sha256 = "b812eb9ed8f5d7005731f5fdc3788bda98bf36be32fd8c0ab7d5c43430a85a1d"

    static func url() throws -> URL {
        if let bundled = Bundle.module.url(forResource: fileName, withExtension: nil, subdirectory: "Fixtures") {
            return bundled
        }
        var repository = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { repository.deleteLastPathComponent() }
        let url = repository.appendingPathComponent("Test").appendingPathComponent(fileName)
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw XCTSkip("The optional user-supplied MP3 is unavailable in this test environment.")
        }
        return url
    }
}

@MainActor
final class ReportedMP3Tests: XCTestCase {
    private let playbackTimeout: TimeInterval = 5

    func testReportedMP3DecodesCompletelyAndProvidesMetadata() async throws {
        let url = try ReportedMP3Fixture.url()
        XCTAssertEqual(url.lastPathComponent, ReportedMP3Fixture.fileName)
        XCTAssertEqual(try sha256(at: url), ReportedMP3Fixture.sha256,
                       "Decode the unchanged user-supplied bytes under their original name.")
        let duration = try await Task.detached {
            try AudioFileValidator.validate(url) { try Task.checkCancellation() }
        }.value
        let metadata = try await PlaylistMediaAccess().metadata(at: url)
        let file = try AVAudioFile(forReading: url)

        XCTAssertEqual(file.processingFormat.sampleRate, 44_100)
        XCTAssertEqual(file.processingFormat.channelCount, 2)
        XCTAssertGreaterThan(duration, 300)
        XCTAssertLessThan(duration, 400)
        XCTAssertEqual(metadata.duration, duration, accuracy: 0.001)
        XCTAssertFalse(metadata.title.isEmpty)
    }

    func testReportedMP3PlaysPausesSeeksResumesAndFinishes() async throws {
        let url = try ReportedMP3Fixture.url()
        XCTAssertEqual(url.lastPathComponent, ReportedMP3Fixture.fileName)
        let audio = AudioPlaybackService()
        defer {
            audio.onTrackFinished = nil
            audio.stop()
        }

        try await audio.loadAndPlay(url: url)
        XCTAssertTrue(audio.state.isPlaying)
        XCTAssertFalse(audio.state.isStarting)
        await waitForProgress(after: 0, audio: audio)

        audio.pauseByUser()
        XCTAssertFalse(audio.state.isPlaying)
        let middle = audio.state.duration / 2
        audio.seek(to: middle)
        XCTAssertEqual(audio.state.currentTime, middle, accuracy: 0.001)
        try await audio.play()?.value
        XCTAssertTrue(audio.state.isPlaying)
        await waitForProgress(after: middle, audio: audio)

        audio.pauseByUser()
        let finished = expectation(description: "Reported MP3 reaches its natural EOF")
        audio.onTrackFinished = { finished.fulfill() }
        audio.seek(to: audio.state.duration - 0.2)
        try await audio.play()?.value
        await fulfillment(of: [finished], timeout: playbackTimeout)

        XCTAssertFalse(audio.state.isPlaying)
        XCTAssertFalse(audio.state.isStarting)
        XCTAssertEqual(audio.state.currentTime, audio.state.duration, accuracy: 0.001)
        XCTAssertNil(audio.state.playbackError)
        audio.stop()
        XCTAssertEqual(audio.state.currentTime, 0)
        XCTAssertEqual(audio.state.duration, 0)
    }

    func testReportedMP3OriginalNameSurvivesFolderListingAndCachedPlayback() async throws {
        let sample = try ReportedMP3Fixture.url()
        XCTAssertEqual(sample.lastPathComponent, ReportedMP3Fixture.fileName)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = directory.appendingPathComponent("Music", isDirectory: true)
        let cacheDirectory = directory.appendingPathComponent("Cache", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let sourceURL = sourceDirectory.appendingPathComponent(ReportedMP3Fixture.fileName)
        try FileManager.default.copyItem(at: sample, to: sourceURL)

        let folders = FolderAccessService(cacheDirectory: cacheDirectory)
        let source = try await folders.makeSource(at: sourceDirectory)
        let listing = try await folders.list(source: source, relativePath: "")
        XCTAssertEqual(listing.entries.map(\.name), [ReportedMP3Fixture.fileName])
        XCTAssertEqual(listing.entries.map(\.relativePath), [ReportedMP3Fixture.fileName])
        let entry = try XCTUnwrap(listing.entries.first)
        XCTAssertEqual(entry.kind, .audio)
        let lease = try await folders.prepare(source: source, entry: entry, priority: .playback)
        let audio = AudioPlaybackService()
        do {
            XCTAssertNotEqual(lease.url, sourceURL, "Folder playback must use the prepared cache.")
            XCTAssertEqual(try sha256(at: lease.url), ReportedMP3Fixture.sha256,
                           "Cache preparation must preserve the exact MP3 contents.")
            try await audio.loadAndPlay(url: lease.url)
            XCTAssertTrue(audio.state.isPlaying)
            await waitForProgress(after: 0, audio: audio)
            XCTAssertNil(audio.state.playbackError)
            audio.stop()
            await folders.release(lease)
            await folders.forget(sourceID: source.id)
        } catch {
            audio.stop()
            await folders.release(lease)
            await folders.forget(sourceID: source.id)
            throw error
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: lease.url.path))
        XCTAssertEqual(try sha256(at: sourceURL), ReportedMP3Fixture.sha256,
                       "Releasing the cache must leave the original source unchanged.")
    }

    private func sha256(at url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private func waitForProgress(after position: TimeInterval, audio: AudioPlaybackService) async {
        let progressed = expectation(description: "Reported MP3 render playback advances")
        let observation = audio.state.$currentTime
            .filter { $0 > position + 0.01 }
            .prefix(1)
            .sink { _ in progressed.fulfill() }
        defer { observation.cancel() }
        await fulfillment(of: [progressed], timeout: playbackTimeout)
    }
}
