import AVFoundation
import Foundation
import PlaybackDomain
import XCTest
@testable import PlayerInfrastructure

final class AudioFileValidationTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"),
            "Generate audio fixtures with Tools/generate_audio_fixtures.py before building the test bundle."
        )
    }

    func testRealSupportedCodecsDecodeToTheEnd() throws {
        for name in ["tone.mp3", "tone.flac", "tone.wav", "tone.aiff", "tone.caf",
                     "tone.aac", "tone.m4a", "tone-alac.m4a"] {
            do {
                let duration = try AudioFileValidator.validate(fixture(name))
                XCTAssertTrue(duration.isFinite && duration > 0, name)
            } catch {
                XCTFail("\(name): \(error)")
            }
        }
    }

    func testEmptyAndDisguisedFilesAreRejectedForEverySupportedExtension() throws {
        let root = try temporaryDirectory()
        for ext in SupportedAudioFormats.fileExtensions {
            let url = root.appendingPathComponent("invalid." + ext)
            try Data().write(to: url)
            XCTAssertThrowsError(try AudioFileValidator.validate(url), "Empty \(ext)")
            try Data("This is text, not encoded audio.".utf8).write(to: url)
            XCTAssertThrowsError(try AudioFileValidator.validate(url), "Disguised \(ext)")
        }
    }

    func testUnsupportedExtensionIsRejectedEvenWhenContentIsDecodable() throws {
        let root = try temporaryDirectory()
        let contents = try Data(contentsOf: fixture("tone.wav"))
        for name in ["tone.txt", "tone.mp4", "tone.ogg", "tone.wma", "tone"] {
            let url = root.appendingPathComponent(name)
            try contents.write(to: url)
            XCTAssertThrowsError(try AudioFileValidator.validate(url), name)
        }
    }

    func testUppercaseAndCommonAIFFAndWAVAliasesAreAccepted() throws {
        let root = try temporaryDirectory()
        for (original, name) in [("tone.wav", "TRACK.WAV"), ("tone.wav", "track.wave"),
                                 ("tone.aiff", "track.AIF"), ("tone.flac", "TRACK.FLAC")] {
            let url = root.appendingPathComponent(name)
            try FileManager.default.copyItem(at: fixture(original), to: url)
            XCTAssertGreaterThan(try AudioFileValidator.validate(url), 0)
        }
    }

    func testNonemptyAudioContainerWithoutSamplesIsRejected() throws {
        let root = try temporaryDirectory()
        let url = root.appendingPathComponent("empty.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        do { _ = try AVAudioFile(forWriting: url, settings: format.settings) }
        XCTAssertGreaterThan(try Data(contentsOf: url).count, 0)
        XCTAssertThrowsError(try AudioFileValidator.validate(url))
    }

    func testTruncatedHeadersAreRejected() throws {
        let root = try temporaryDirectory()
        for name in ["tone.mp3", "tone.flac", "tone.wav", "tone.m4a"] {
            let url = root.appendingPathComponent(name)
            try Data(contentsOf: fixture(name)).prefix(12).write(to: url)
            XCTAssertThrowsError(try AudioFileValidator.validate(url), name)
        }
    }

    func testCancellationStopsValidation() throws {
        var checks = 0
        XCTAssertThrowsError(try AudioFileValidator.validate(fixture("tone.wav")) {
            checks += 1
            if checks == 3 { throw CancellationError() }
        }) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(checks, 3)
    }

    func testTruncatedFLACPayloadIsRejectedEvenWithAnIntactHeader() throws {
        let root = try temporaryDirectory()
        let url = root.appendingPathComponent("truncated.flac")
        let complete = try Data(contentsOf: fixture("tone.flac"))
        try complete.dropLast(500).write(to: url)
        XCTAssertThrowsError(try AudioFileValidator.validate(url))
    }

    func testTruncatedWAVPayloadIsRejectedEvenWithAnIntactHeader() throws {
        let root = try temporaryDirectory()
        let url = root.appendingPathComponent("truncated.wav")
        let complete = try Data(contentsOf: fixture("tone.wav"))
        try complete.dropLast(500).write(to: url)

        XCTAssertThrowsError(try AudioFileValidator.validate(url),
                             "A WAV with missing samples must not become an apparently valid shorter track.")
    }

    func testOversizedWAVDataChunkIsRejectedWhenRIFFSizeMatchesFile() throws {
        let root = try temporaryDirectory()
        let url = root.appendingPathComponent("invalid-chunk.wav")
        var truncated = Data(try Data(contentsOf: fixture("tone.wav")).dropLast(500))
        replaceUInt32(UInt32(truncated.count - 8), at: 4, in: &truncated)
        try truncated.write(to: url)

        XCTAssertThrowsError(try AudioFileValidator.validate(url),
                             "The data chunk must fit inside RIFF even when the outer size matches the file.")
    }

    func testWAVAcceptsOddSizedMetadataChunksWithPadding() throws {
        let root = try temporaryDirectory()
        let original = try Data(contentsOf: fixture("tone.wav"))
        let chunk = Data("JUNK".utf8) + Data([3, 0, 0, 0, 1, 2, 3, 0])
        for insertionOffset in [12, original.count] {
            var contents = original
            contents.insert(contentsOf: chunk, at: insertionOffset)
            replaceUInt32(UInt32(contents.count - 8), at: 4, in: &contents)
            let url = root.appendingPathComponent("metadata-\(insertionOffset).wav")
            try contents.write(to: url)

            XCTAssertEqual(try AudioFileValidator.validate(url), 0.1, accuracy: 0.0001,
                           "Optional odd-sized chunks before or after audio must preserve valid playback.")
        }
    }

    func testWAVRejectsChunkSizeThatExceedsContainerWithoutAllocatingItsPayload() throws {
        let root = try temporaryDirectory()
        var contents = try Data(contentsOf: fixture("tone.wav"))
        let oversized = Data("JUNK".utf8) + Data(repeating: 0xFF, count: 4)
        contents.insert(contentsOf: oversized, at: 12)
        replaceUInt32(UInt32(contents.count - 8), at: 4, in: &contents)
        let url = root.appendingPathComponent("oversized-chunk.wav")
        try contents.write(to: url)

        XCTAssertThrowsError(try AudioFileValidator.validate(url),
                             "A declared UInt32.max chunk size must fail bounds checks without overflow.")
    }

    private func replaceUInt32(_ value: UInt32, at offset: Int, in data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.replaceSubrange(offset..<(offset + 4), with: bytes)
        }
    }

    @MainActor
    func testMetadataRejectsInvalidFilesAndUsesDecodedDuration() async throws {
        let media = PlaylistMediaAccess()
        let metadata = try await media.metadata(at: fixture("tone.flac"))
        XCTAssertGreaterThan(metadata.duration, 0)
        XCTAssertEqual(metadata.title, "tone")
        let root = try temporaryDirectory()
        let invalid = root.appendingPathComponent("broken.mp3")
        try Data("broken audio".utf8).write(to: invalid)
        do {
            _ = try await media.metadata(at: invalid)
            XCTFail("Invalid content must fail before a playlist row can be created")
        } catch is CancellationError {
            XCTFail("Validation must fail for the content, not cancellation")
        } catch { }
    }
}
