import CoreGraphics
import Foundation
@testable import PlayerFeature
import XCTest

final class AmbientSpectrumTests: XCTestCase {
    func testInvalidAndOversizedSamplesCannotCorruptTheGPUBuffer() {
        var spectrum = AmbientSpectrum()
        let malformed: [CGFloat] = [.nan, .infinity, -.infinity, -0.5, 0.25, 2, .greatestFiniteMagnitude]
        spectrum.update(malformed + Array(repeating: 0.5, count: 100))
        spectrum.advance(by: 10)

        XCTAssertEqual(spectrum.levels.count, 72)
        XCTAssertTrue(spectrum.levels.allSatisfy { $0.isFinite && (0...1).contains($0) })
        XCTAssertEqual(Array(spectrum.levels.prefix(4)), [0, 0, 0, 0])
        XCTAssertEqual(spectrum.levels[4], 0.25, accuracy: 0.0001)
        XCTAssertEqual(spectrum.levels[5], 1, accuracy: 0.0001)
        XCTAssertEqual(spectrum.levels[6], 1, accuracy: 0.0001)
        XCTAssertEqual(spectrum.levels[71], 0.5, accuracy: 0.0001)
    }

    func testShortFramesDoNotRetainOldFrequencyBands() {
        var spectrum = AmbientSpectrum()
        spectrum.update(Array(repeating: 1, count: 72))
        spectrum.advance(by: 1)
        spectrum.update([0.75])
        spectrum.advance(by: 5)

        XCTAssertEqual(spectrum.levels.count, 72)
        XCTAssertEqual(spectrum.levels[0], 0.75, accuracy: 0.0001)
        XCTAssertTrue(spectrum.levels.dropFirst().allSatisfy { $0 == 0 })
    }

    func testPauseResetClearsDisplayedAndPendingSamples() {
        var spectrum = AmbientSpectrum()
        spectrum.update(Array(repeating: 1, count: 72))
        spectrum.advance(by: 0.1)
        XCTAssertGreaterThan(spectrum.levels[0], 0)

        spectrum.reset()
        spectrum.advance(by: 1)

        XCTAssertEqual(spectrum.levels.count, 72)
        XCTAssertTrue(spectrum.levels.allSatisfy { $0 == 0 }, "Resume must not resurrect pre-pause targets.")
    }

    func testAttackIsResponsiveAndReleaseFallsWithoutOvershooting() {
        var rising = AmbientSpectrum()
        rising.update([1])
        rising.advance(by: 0.05)
        let attackStep = rising.levels[0]
        XCTAssertGreaterThan(attackStep, 0)
        XCTAssertLessThan(attackStep, 1)

        var falling = AmbientSpectrum()
        falling.update([1])
        falling.advance(by: 10)
        falling.update([0])
        falling.advance(by: 0.05)
        XCTAssertGreaterThan(attackStep, 1 - falling.levels[0], "Attack should be faster than release.")

        var previous = falling.levels[0]
        for _ in 0..<30 {
            falling.advance(by: 0.05)
            XCTAssertLessThanOrEqual(falling.levels[0], previous)
            XCTAssertGreaterThanOrEqual(falling.levels[0], 0)
            previous = falling.levels[0]
        }
    }

    func testSmoothingDependsOnElapsedTimeInsteadOfFrameCount() {
        var atThirtyFPS = AmbientSpectrum()
        var atFifteenFPS = AmbientSpectrum()
        var oneStep = AmbientSpectrum()
        atThirtyFPS.update([0.8])
        atFifteenFPS.update([0.8])
        oneStep.update([0.8])

        for _ in 0..<6 { atThirtyFPS.advance(by: 1.0 / 30.0) }
        for _ in 0..<3 { atFifteenFPS.advance(by: 1.0 / 15.0) }
        oneStep.advance(by: 0.2)

        XCTAssertEqual(atThirtyFPS.levels[0], atFifteenFPS.levels[0], accuracy: 0.00001)
        XCTAssertEqual(atThirtyFPS.levels[0], oneStep.levels[0], accuracy: 0.00001)
    }

    func testSilenceAndInvalidFrameTimesNeverCreateMotion() {
        var spectrum = AmbientSpectrum()
        spectrum.update([])
        for elapsed in [0.0, -1.0, .nan, .infinity, 0.05, 1.0] {
            spectrum.advance(by: elapsed)
        }
        XCTAssertTrue(spectrum.levels.allSatisfy { $0 == 0 })

        spectrum.update([1])
        spectrum.advance(by: 0.05)
        let before = spectrum.levels
        for elapsed in [0.0, -1.0, .nan, .infinity] { spectrum.advance(by: elapsed) }
        XCTAssertEqual(spectrum.levels, before, "Invalid timestamps must not contaminate the next frame.")
    }
}
