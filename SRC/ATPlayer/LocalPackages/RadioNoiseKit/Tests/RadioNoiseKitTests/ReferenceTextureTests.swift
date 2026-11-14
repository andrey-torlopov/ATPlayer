import Foundation
import RadioNoiseKit
import XCTest

final class ReferenceTextureTests: XCTestCase {
    private func render(_ preset: RadioNoisePreset, rate: Double = 48_000,
                        seconds: Int = 20, block: Int = 256) throws -> [Float] {
        let generator = try XCTUnwrap(RadioNoiseCreate(rate, 1, 20_261_114))
        defer { RadioNoiseDestroy(generator) }
        var parameters = RadioNoiseParametersForPreset(preset)
        parameters.masterLevel = 1
        RadioNoiseSetParameters(generator, parameters)
        var samples = [Float](repeating: 0, count: Int(rate) * seconds)
        samples.withUnsafeMutableBufferPointer { buffer in
            for offset in stride(from: 0, to: buffer.count, by: block) {
                RadioNoiseRender(generator, buffer.baseAddress?.advanced(by: offset), nil,
                                 UInt32(min(block, buffer.count - offset)))
            }
        }
        return samples
    }

    private func envelope(_ samples: [Float], window: Int = 480) -> [Double] {
        // Fixed audio frames, not sleeps; discard only the 50 ms control ramp.
        stride(from: 2_400, through: samples.count - window, by: window).map { offset in
            let sum = samples[offset..<(offset + window)].reduce(0.0) { $0 + Double($1) * Double($1) }
            return (sum / Double(window)).squareRoot()
        }.sorted()
    }

    private func rangeDB(_ envelope: [Double]) -> Double {
        let low = envelope[envelope.count / 10]
        let high = envelope[envelope.count * 9 / 10]
        return 20 * log10(high / low)
    }

    func testRetroProfilesHaveDistinctDepthAndStablePresetAliases() throws {
        XCTAssertEqual(RadioNoisePresetRetro07, RadioNoisePresetRetro)
        XCTAssertEqual(RadioNoisePresetUniden12, RadioNoisePresetSquelch)
        let deep = envelope(try render(RadioNoisePresetRetro07))
        let dense = envelope(try render(RadioNoisePresetRetro08))
        XCTAssertGreaterThan(rangeDB(deep), 12)
        XCTAssertLessThan(rangeDB(dense), 12)
        XCTAssertGreaterThan(rangeDB(deep) - rangeDB(dense), 5)
    }

    func testUnidenHasPersistentBedAndBurstsRatherThanIsolatedPuffs() throws {
        let windows = envelope(try render(RadioNoisePresetUniden12))
        // The supplied 12 contains a continuously active bed. Its upper bursts
        // should remain substantially louder without leaving near-silent gaps.
        XCTAssertGreaterThan(windows[windows.count / 10], 0.015)
        XCTAssertGreaterThan(rangeDB(windows), 4)
        XCTAssertLessThan(rangeDB(windows), 14)
        XCTAssertGreaterThan(windows[windows.count * 99 / 100] / windows[windows.count / 2], 1.6)
    }

    func testNewReferenceProfilesAreFiniteAtRateExtremesAndBlockIndependent() throws {
        for preset in [RadioNoisePresetRetro07, RadioNoisePresetRetro08, RadioNoisePresetUniden12] {
            for rate in [8_000.0, 384_000.0] {
                let samples = try render(preset, rate: rate, seconds: 2)
                XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) <= 1 })
                XCTAssertTrue(samples.contains { $0 != 0 })
            }
            XCTAssertEqual(try render(preset, seconds: 2, block: 127),
                           try render(preset, seconds: 2, block: 1_024))
        }
    }
}
