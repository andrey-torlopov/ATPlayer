import Foundation
import RadioNoiseKit
import XCTest

final class RadioNoiseKitTests: XCTestCase {
    private func generator(rate: Double = 48_000, channels: UInt32 = 2, seed: UInt64 = 17) throws -> OpaquePointer {
        try XCTUnwrap(RadioNoiseCreate(rate, channels, seed))
    }

    private func render(_ generator: OpaquePointer, frames: Int, block: Int = 256) -> [Float] {
        var result: [Float] = []
        for start in stride(from: 0, to: frames, by: block) {
            let count = min(block, frames - start)
            var left = [Float](repeating: 0, count: count)
            var right = left
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in RadioNoiseRender(generator, l.baseAddress, r.baseAddress, UInt32(count)) }
            }
            result += left
        }
        return result
    }

    func testSeedAndResultAreIndependentOfBlockPartition() throws {
        let a = try generator()
        let b = try generator()
        defer { RadioNoiseDestroy(a); RadioNoiseDestroy(b) }
        XCTAssertEqual(render(a, frames: 48_000, block: 127), render(b, frames: 48_000, block: 1_024))
    }

    func testResetReproducesOriginalSequence() throws {
        let value = try generator(seed: 42)
        defer { RadioNoiseDestroy(value) }
        let first = render(value, frames: 32_000)
        _ = render(value, frames: 10_000)
        RadioNoiseReset(value, 42)
        XCTAssertEqual(first, render(value, frames: 32_000))
        RadioNoiseReset(value, 43)
        XCTAssertNotEqual(first, render(value, frames: 32_000))
    }

    func testEveryIndependentComponentProducesBoundedAudio() throws {
        for component in 0..<5 {
            let value = try generator()
            defer { RadioNoiseDestroy(value) }
            var parameters = RadioNoiseParameters(masterLevel: 1, character: 0.7, hissLevel: 0,
                crackleLevel: 0, resonanceLevel: 0, chatterLevel: 0, squelchLevel: 0)
            switch component {
            case 0: parameters.hissLevel = 1
            case 1: parameters.crackleLevel = 1
            case 2: parameters.resonanceLevel = 1
            case 3: parameters.chatterLevel = 1
            default: parameters.squelchLevel = 1
            }
            RadioNoiseSetParameters(value, parameters)
            let output = render(value, frames: 96_000)
            XCTAssertTrue(output.allSatisfy { $0.isFinite && abs($0) <= 1 })
            XCTAssertGreaterThan(output.reduce(0.0) { $0 + Double($1) * Double($1) }, 0.001)
        }
    }

    func testMasterIsMonotonicAndExactZeroDoesNotAdvanceRandomness() throws {
        let dry = try generator()
        let fresh = try generator()
        defer { RadioNoiseDestroy(dry); RadioNoiseDestroy(fresh) }
        var parameters = RadioNoiseDefaultParameters()
        parameters.masterLevel = 0
        RadioNoiseSetParameters(dry, parameters)
        RadioNoiseSetParameters(fresh, parameters)
        _ = render(fresh, frames: 4_800)
        XCTAssertTrue(render(dry, frames: 48_000).allSatisfy { $0 == 0 })
        parameters.masterLevel = 0.2
        RadioNoiseSetParameters(dry, parameters)
        RadioNoiseSetParameters(fresh, parameters)
        // Both control ramps settled in silence; only one context waited longer.
        let resumed = render(dry, frames: 48_000)
        let initial = render(fresh, frames: 48_000)
        XCTAssertEqual(resumed, initial)

        var previous = 0.0
        for level: Float in [0.1, 0.4, 1] {
            let value = try generator()
            defer { RadioNoiseDestroy(value) }
            parameters.masterLevel = level
            RadioNoiseSetParameters(value, parameters)
            let output = render(value, frames: 48_000).dropFirst(4_800)
            let energy = output.reduce(0.0) { $0 + Double($1) * Double($1) }
            XCTAssertGreaterThan(energy, previous)
            previous = energy
        }
    }

    func testZeroComponentsAreSilentAndNonfiniteParametersAreSanitized() throws {
        let value = try generator()
        defer { RadioNoiseDestroy(value) }
        RadioNoiseSetParameters(value, RadioNoiseParameters(masterLevel: 1, character: .nan,
            hissLevel: .nan, crackleLevel: -.infinity, resonanceLevel: -1, chatterLevel: 0, squelchLevel: 0))
        XCTAssertTrue(render(value, frames: 48_000).allSatisfy { $0 == 0 })
    }

    func testMonoAndSampleRateMatrix() throws {
        for rate in [8_000.0, 44_100.0, 48_000.0, 96_000.0, 192_000.0, 384_000.0] {
            let value = try generator(rate: rate, channels: 1)
            defer { RadioNoiseDestroy(value) }
            var samples = [Float](repeating: 0, count: Int(rate))
            samples.withUnsafeMutableBufferPointer { RadioNoiseRender(value, $0.baseAddress, nil, UInt32($0.count)) }
            XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) <= 1 })
            XCTAssertTrue(samples.contains { $0 != 0 })
        }
    }

    func testResonantPresetsRemainFiniteAtLowestSupportedRate() throws {
        for preset in [RadioNoisePresetRinging, RadioNoisePresetSquelch] {
            let value = try generator(rate: 8_000)
            defer { RadioNoiseDestroy(value) }
            var parameters = RadioNoiseParametersForPreset(preset)
            parameters.masterLevel = 1
            RadioNoiseSetParameters(value, parameters)
            XCTAssertTrue(render(value, frames: 80_000).allSatisfy { $0.isFinite && abs($0) <= 1 })
        }
    }

    func testFrameAdapterMatchesBlockRendering() throws {
        let a = try generator()
        let b = try generator()
        defer { RadioNoiseDestroy(a); RadioNoiseDestroy(b) }
        let whole = render(a, frames: 8_192, block: 8_192)
        RadioNoiseBeginBlock(b)
        var frames: [Float] = []
        for _ in 0..<8_192 {
            let output = RadioNoiseNextFrame(b)
            XCTAssertTrue((0...1).contains(output.activity))
            frames.append(output.left)
        }
        XCTAssertEqual(whole, frames)
    }

    func testRejectsInvalidConfiguration() {
        XCTAssertNil(RadioNoiseCreate(.nan, 2, 0))
        XCTAssertNil(RadioNoiseCreate(0, 1, 0))
        XCTAssertNil(RadioNoiseCreate(48_000, 3, 0))
    }
}
