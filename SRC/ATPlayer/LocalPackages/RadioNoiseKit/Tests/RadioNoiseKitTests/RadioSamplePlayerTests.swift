import AVFoundation
import Foundation
import RadioNoiseKit
import XCTest

final class RadioSamplePlayerTests: XCTestCase {
    private func create(_ source: [Float], rate: Double = 8_000,
                        seed: UInt64 = 140) throws -> OpaquePointer {
        try source.withUnsafeBufferPointer {
            try XCTUnwrap(RadioSampleCreate(rate, $0.baseAddress, UInt64($0.count), seed))
        }
    }

    private func render(_ player: OpaquePointer, count: Int, block: Int = 256) -> [Float] {
        var samples = [Float](repeating: 0, count: count)
        samples.withUnsafeMutableBufferPointer { buffer in
            for offset in stride(from: 0, to: count, by: block) {
                RadioSampleRender(player, buffer.baseAddress?.advanced(by: offset),
                                  UInt32(min(block, count - offset)))
            }
        }
        return samples
    }

    func testCopiesPCMAndPlaysAnUnmodifiedContiguousOriginalSection() throws {
        let original = (1...16_000).map { Float($0) / 32_768 }
        var input = original
        let player = try create(input)
        defer { RadioSampleDestroy(player) }
        input = [Float](repeating: 0, count: input.count)
        let output = render(player, count: 8_000)
        let offset = try XCTUnwrap(original.firstIndex(of: try XCTUnwrap(output.first)))
        XCTAssertLessThanOrEqual(offset, original.count / 4)
        XCTAssertEqual(output, Array(original[offset..<(offset + output.count)]))
        let expectedRMS = sqrt(original.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(original.count))
        XCTAssertEqual(Double(RadioSampleRMS(player)), expectedRMS, accuracy: 0.0000001)
        XCTAssertTrue(input.allSatisfy { $0 == 0 })
    }

    func testReference12PreservesThirtySecondsOfActualRecordingExactly() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let referenceURL = packageRoot.appendingPathComponent("Sources/RadioNoiseAssets/Resources/Uniden12.mono.wav")
        let file = try AVAudioFile(forReading: referenceURL, commonFormat: .pcmFormatFloat32, interleaved: false)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        XCTAssertEqual(file.processingFormat.sampleRate, 48_000)
        let chunk = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384))
        var source: [Float] = []
        source.reserveCapacity(Int(file.length))
        while source.count < Int(file.length) {
            try file.read(into: chunk, frameCount: min(chunk.frameCapacity, AVAudioFrameCount(Int(file.length) - source.count)))
            guard chunk.frameLength > 0 else { XCTFail("Reference recording decode stopped early"); return }
            let channel = try XCTUnwrap(chunk.floatChannelData?[0])
            source.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(chunk.frameLength)))
        }
        let player = try create(source, rate: file.processingFormat.sampleRate)
        defer { RadioSampleDestroy(player) }
        let output = render(player, count: 48_000 * 30)
        let signature = output.prefix(32)
        let offset = try XCTUnwrap((0...source.count / 4).first { candidate in
            source[candidate] == output[0] && source[candidate..<(candidate + signature.count)].elementsEqual(signature)
        })
        XCTAssertEqual(output, Array(source[offset..<(offset + output.count)]),
                       "Actual recording must retain every source sample, burst, silence and pitch between splices")
    }

    func testResetAndBlockPartitionReproduceLongSplicedSequence() throws {
        let source = (0..<8_700).map { Float(0.4 * sin(2 * Double.pi * 37 * Double($0) / 8_000)) }
        let a = try create(source)
        let b = try create(source)
        defer { RadioSampleDestroy(a); RadioSampleDestroy(b) }
        let baseline = render(a, count: 80_000, block: 127)
        XCTAssertEqual(baseline, render(b, count: 80_000, block: 1_024))
        RadioSampleReset(a, 140)
        XCTAssertEqual(baseline, render(a, count: 80_000))
        RadioSampleReset(a, 141)
        XCTAssertNotEqual(Array(baseline.prefix(1_000)), render(a, count: 1_000))
    }

    func testEndSplicesAreSmoothAndDoNotRaiseConstantGain() throws {
        let source = (0..<8_700).map { Float(0.4 * sin(2 * Double.pi * 20 * Double($0) / 8_000)) }
        let player = try create(source)
        defer { RadioSampleDestroy(player) }
        let output = render(player, count: 80_000)
        let largestStep = zip(output, output.dropFirst()).map { abs($1 - $0) }.max() ?? 0
        XCTAssertLessThan(largestStep, 0.0105, "No hard jump at the recording end or crossfade boundaries")
        XCTAssertTrue(output.allSatisfy { $0.isFinite && abs($0) <= 0.400001 })

        let constant = try create([Float](repeating: 0.3, count: 8_000))
        defer { RadioSampleDestroy(constant) }
        XCTAssertTrue(render(constant, count: 32_000).allSatisfy { abs($0 - 0.3) < 0.0000001 })
    }

    func testPitchAndPlaybackRateStayUnchangedBeforeSplice() throws {
        for rate in [8_000.0, 44_100.0, 48_000.0, 96_000.0, 384_000.0] {
            let source = (0..<Int(rate * 2)).map { Float(0.3 * sin(2 * Double.pi * 997 * Double($0) / rate)) }
            let player = try create(source, rate: rate)
            defer { RadioSampleDestroy(player) }
            let output = render(player, count: Int(rate))
            let crossings = zip(output, output.dropFirst()).filter { $0 <= 0 && $1 > 0 }.count
            XCTAssertTrue((996...998).contains(crossings), "One second must retain the 997 Hz source pitch at \(rate) Hz")
        }
    }

    func testInvalidInputsAreRejectedAndShortestClipCanSplice() throws {
        let source = [Float](repeating: 0.2, count: 8)
        source.withUnsafeBufferPointer { buffer in
            XCTAssertNil(RadioSampleCreate(.nan, buffer.baseAddress, 8, 1))
            XCTAssertNil(RadioSampleCreate(7_999, buffer.baseAddress, 8, 1))
            XCTAssertNil(RadioSampleCreate(384_001, buffer.baseAddress, 8, 1))
            XCTAssertNil(RadioSampleCreate(8_000, buffer.baseAddress, 7, 1))
            XCTAssertNil(RadioSampleCreate(8_000, buffer.baseAddress, .max, 1))
        }
        XCTAssertNil(RadioSampleCreate(8_000, nil, 8, 1))
        for bad: Float in [.nan, .infinity, -1.01, 1.01] {
            var input = source
            input[4] = bad
            input.withUnsafeBufferPointer { buffer in
                XCTAssertNil(RadioSampleCreate(8_000, buffer.baseAddress, 8, 1))
            }
        }
        let player = try create(source)
        defer { RadioSampleDestroy(player) }
        XCTAssertTrue(render(player, count: 1_024).allSatisfy { $0 == 0.2 })
        XCTAssertEqual(RadioSampleNextFrame(nil), 0)
        XCTAssertEqual(RadioSampleRMS(nil), 0)
    }
}
