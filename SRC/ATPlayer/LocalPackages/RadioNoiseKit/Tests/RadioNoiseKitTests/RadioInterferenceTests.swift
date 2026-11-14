import RadioNoiseKit
import XCTest

final class RadioInterferenceTests: XCTestCase {
    private let rate = 8_000.0

    private struct FrameSnapshot: Equatable {
        let musicGain: Float
        let noiseRatio: Float
        let noiseSample: Float
        let envelope: Float
        let phase: Int
        let eventStarted: Bool

        init(_ frame: RadioInterferenceFrame) {
            musicGain = frame.musicGain
            noiseRatio = frame.noiseRatio
            noiseSample = frame.noiseSample
            envelope = frame.envelope
            phase = Int(frame.phase.rawValue)
            eventStarted = frame.eventStarted
        }
    }

    func testPlateauBalanceAndTimingAreIndependentOfIntensity() throws {
        let levels: [Float] = [0, 1, 2, 5, 8, 10]
        let expectedMusic: [Float] = [1, 0.895, 0.83, 0.6875, 0.53, 0.425]
        let expectedNoise: [Float] = [0, 0.14, 0.24, 0.4125, 0.57, 0.675]
        let expectedBeds: [Float] = [0, 0.07, 0.14, 0.275, 0.36, 0.4125]
        var positiveStarts: [Int] = []
        for index in levels.indices {
            let generator = try XCTUnwrap(RadioInterferenceCreate(rate, 71))
            defer { RadioInterferenceDestroy(generator) }
            var start: Int?
            var holds = 0
            var peakEnvelope: Float = 0
            let expectedBed = expectedBeds[index]
            var observedBedBeforeEvent = false
            var returnedToBed = false
            var lastMusic: Float = 1
            for frame in 0..<120_000 {
                let output = RadioInterferenceNextFrame(generator, levels[index], levels[index] / 2, true, frame.isMultiple(of: 2) ? 0.1 : -0.1, 0.2)
                if output.eventStarted { start = frame }
                if start == nil && frame > 1_600 && levels[index] > 0 {
                    observedBedBeforeEvent = true
                    XCTAssertEqual(output.musicGain, 1)
                    XCTAssertEqual(output.noiseRatio, expectedBed, accuracy: 0.00001)
                    XCTAssertGreaterThan(abs(output.noiseSample), 0)
                }
                if output.phase == RadioInterferencePhaseHold {
                    holds += 1
                    XCTAssertEqual(output.musicGain, expectedMusic[index], accuracy: 0.00001)
                    XCTAssertEqual(output.noiseRatio, expectedNoise[index], accuracy: 0.00001)
                    XCTAssertEqual(abs(output.noiseSample), expectedNoise[index] * 0.2, accuracy: 0.002)
                }
                if start != nil && output.phase == RadioInterferencePhaseIdle {
                    returnedToBed = output.musicGain == 1 && abs(output.noiseSample) > 0
                    XCTAssertEqual(output.noiseRatio, expectedBed, accuracy: 0.00001)
                    break
                }
                XCTAssertLessThan(abs(output.musicGain - lastMusic), 0.001, "No step at attack/hold/release boundaries")
                lastMusic = output.musicGain
                peakEnvelope = max(peakEnvelope, output.envelope)
            }
            if levels[index] == 0 {
                XCTAssertNil(start)
                XCTAssertEqual(peakEnvelope, 0)
            } else {
                positiveStarts.append(try XCTUnwrap(start))
                XCTAssertTrue((Int(3 * rate)..<Int(6 * rate)).contains(start ?? -1))
                XCTAssertTrue((Int(rate)..<Int(6 * rate)).contains(holds))
                XCTAssertEqual(peakEnvelope, 1)
                XCTAssertTrue(observedBedBeforeEvent)
                XCTAssertTrue(returnedToBed)
            }
        }
        XCTAssertEqual(Set(positiveStarts).count, 1)
    }

    func testHoldDurationsVaryWithinOneToSixSeconds() throws {
        var durations = Set<Int>()
        for seed in UInt64(0)..<12 {
            let generator = try XCTUnwrap(RadioInterferenceCreate(rate, seed))
            defer { RadioInterferenceDestroy(generator) }
            var holdFrames = 0
            for _ in 0..<104_000 {
                if RadioInterferenceNextFrame(generator, 10, 2, true, 0.1, 0.2).phase == RadioInterferencePhaseHold {
                    holdFrames += 1
                }
            }
            XCTAssertTrue((8_000..<48_000).contains(holdFrames))
            durations.insert(holdFrames)
        }
        XCTAssertGreaterThan(durations.count, 8)
    }

    func testResetReproducesSequenceAndIneligibleFramesDoNotCreatePauseDebt() throws {
        let generator = try XCTUnwrap(RadioInterferenceCreate(rate, 42))
        defer { RadioInterferenceDestroy(generator) }
        func sequence() -> [FrameSnapshot] {
            (0..<104_000).map { _ in FrameSnapshot(RadioInterferenceNextFrame(generator, 10, 2, true, 0.1, 0.2)) }
        }
        let initial = sequence()
        RadioInterferenceReset(generator, 42)
        XCTAssertEqual(sequence(), initial)
        RadioInterferenceReset(generator, 42)
        for _ in 0..<800_000 {
            let output = RadioInterferenceNextFrame(generator, 10, 2, false, 0.1, 0.2)
            XCTAssertEqual(output.phase, RadioInterferencePhaseIdle)
            XCTAssertEqual(output.musicGain, 1)
            XCTAssertGreaterThan(output.noiseSample, 0)
        }
        for _ in 0..<24_000 {
            XCTAssertFalse(RadioInterferenceNextFrame(generator, 10, 2, true, 0.1, 0.2).eventStarted)
        }
    }

    func testDisablingDuringHoldRampsToExactCleanWithinTwoHundredMilliseconds() throws {
        let generator = try XCTUnwrap(RadioInterferenceCreate(rate, 17))
        defer { RadioInterferenceDestroy(generator) }
        var output = RadioInterferenceNextFrame(generator, 10, 2, true, 0.1, 0.2)
        for _ in 0..<104_000 {
            if output.phase == RadioInterferencePhaseHold { break }
            output = RadioInterferenceNextFrame(generator, 10, 2, true, 0.1, 0.2)
        }
        XCTAssertEqual(output.phase, RadioInterferencePhaseHold)
        var previous = output.musicGain
        for _ in 0..<1_600 {
            output = RadioInterferenceNextFrame(generator, 0, 0, true, 0.1, 0.2)
            XCTAssertGreaterThanOrEqual(output.musicGain, previous)
            XCTAssertLessThan(output.musicGain - previous, 0.001)
            previous = output.musicGain
        }
        XCTAssertEqual(output.musicGain, 1)
        XCTAssertEqual(output.noiseSample, 0)
        XCTAssertEqual(output.noiseRatio, 0)
    }

    func testBackgroundRampsIndependentlyAndReturnsToExactClean() throws {
        let generator = try XCTUnwrap(RadioInterferenceCreate(rate, 17))
        defer { RadioInterferenceDestroy(generator) }
        RadioInterferenceSetNoiseRMS(generator, 0.1)
        for _ in 0..<1_600 {
            let output = RadioInterferenceNextFrame(generator, 0, 0, false, 0.1, 0.2)
            XCTAssertEqual(output.musicGain, 1)
            XCTAssertEqual(output.noiseRatio, 0)
            XCTAssertEqual(output.noiseSample, 0)
        }
        var previous: Float = 0
        for level: Float in [1, 10] {
            for _ in 0..<1_600 {
                let output = RadioInterferenceNextFrame(generator, 10, level, false, 0.1, 0.2)
                XCTAssertEqual(output.phase, RadioInterferencePhaseIdle)
                XCTAssertEqual(output.musicGain, 1)
                XCTAssertGreaterThanOrEqual(output.noiseRatio, previous)
                // The final target snap absorbs accumulated Float rounding.
                XCTAssertLessThan(output.noiseRatio - previous, 0.0008)
                previous = output.noiseRatio
            }
            XCTAssertEqual(previous, level == 1 ? 0.14 : 0.675, accuracy: 0.000001)
        }
        for _ in 0..<1_600 {
            let output = RadioInterferenceNextFrame(generator, 0, 0, false, 0.1, 0.2)
            XCTAssertEqual(output.musicGain, 1)
            XCTAssertLessThanOrEqual(output.noiseRatio, previous)
            XCTAssertLessThan(previous - output.noiseRatio, 0.0013)
            previous = output.noiseRatio
        }
        XCTAssertEqual(previous, 0)
        for _ in 0..<3_200 {
            let output = RadioInterferenceNextFrame(generator, 0, 0, true, 0.1, 0.2)
            XCTAssertEqual(output.noiseRatio, 0)
            XCTAssertEqual(output.noiseSample, 0)
            XCTAssertEqual(output.musicGain, 1)
            XCTAssertFalse(output.eventStarted)
        }
    }

    func testContinuousBedAndEventsAreIndependentOfHostBlockPartition() throws {
        let generator = try XCTUnwrap(RadioInterferenceCreate(rate, 42))
        defer { RadioInterferenceDestroy(generator) }
        RadioInterferenceSetNoiseRMS(generator, 0.1)
        func sequence(blockSize: Int) -> [FrameSnapshot] {
            let count = 320_000
            var output: [FrameSnapshot] = []
            output.reserveCapacity(count)
            for block in stride(from: 0, to: count, by: blockSize) {
                for frame in block..<min(block + blockSize, count) {
                    output.append(FrameSnapshot(RadioInterferenceNextFrame(generator, 10, 2, true,
                        frame.isMultiple(of: 2) ? 0.1 : -0.1, 0.2)))
                }
            }
            return output
        }
        let baseline = sequence(blockSize: 127)
        XCTAssertGreaterThanOrEqual(baseline.filter(\.eventStarted).count, 2)
        RadioInterferenceReset(generator, 42)
        XCTAssertEqual(sequence(blockSize: 1_024), baseline)
        RadioInterferenceReset(generator, 43)
        XCTAssertNotEqual(sequence(blockSize: 1_024), baseline)
    }

    func testIndependentBackgroundAndPeakStayOrderedForAllControlPairs() throws {
        let pairs: [(main: Float, background: Float, bed: Float, peak: Float)] = [
            (10, 0, 0, 0.675), (10, 3, 0.3075, 0.675), (10, 7, 0.5175, 0.675),
            (10, 10, 0.675, 0.675), (2, 9, 0.6225, 0.6225), (0, 10, 0.675, 0.675), (100, -100, 0, 0.675)
        ]
        for (main, background, bed, peak) in pairs {
            let generator = try XCTUnwrap(RadioInterferenceCreate(rate, 17))
            defer { RadioInterferenceDestroy(generator) }
            RadioInterferenceSetNoiseRMS(generator, 0.1)
            var hasIdle = false
            var hasHold = false
            for frame in 0..<104_000 {
                let output = RadioInterferenceNextFrame(generator, main, background, true, 0.1, 0.2)
                guard frame >= 1_600 else { continue }
                XCTAssertGreaterThanOrEqual(output.noiseRatio, bed - 0.000001)
                XCTAssertLessThanOrEqual(output.noiseRatio, peak + 0.000001)
                XCTAssertLessThanOrEqual(output.noiseRatio, 0.675001)
                if output.phase == RadioInterferencePhaseIdle {
                    hasIdle = true
                    XCTAssertEqual(output.noiseRatio, bed, accuracy: 0.000001)
                }
                if output.phase == RadioInterferencePhaseHold {
                    hasHold = true
                    XCTAssertEqual(output.noiseRatio, peak, accuracy: 0.000001)
                    if main == 10 { XCTAssertEqual(output.musicGain, 0.425, accuracy: 0.000001) }
                }
                if bed == peak {
                    XCTAssertEqual(output.noiseRatio, bed, accuracy: 0.000001,
                                   "Equal controls must keep the noise level constant through events")
                }
            }
            XCTAssertTrue(hasIdle)
            if main > 0 { XCTAssertTrue(hasHold) }
        }
    }

    func testNewMaximumMatchesTheOriginalLevelSevenCurve() throws {
        let generator = try XCTUnwrap(RadioInterferenceCreate(rate, 71))
        defer { RadioInterferenceDestroy(generator) }
        RadioInterferenceSetNoiseRMS(generator, 0.1)
        // Use the original C++ curve's fused multiply-add arithmetic rather
        // than decimal literals rounded independently from that calculation.
        let originalSevenNoise = Float(0.30).addingProduct(0.075, 7 - 2)
        let originalSevenMusicLoss = Float(0.20).addingProduct(0.075, 7 - 2)
        var observedPhases = Set<Int>()
        for frame in 0..<120_000 {
            let output = RadioInterferenceNextFrame(generator, 10, 10, true, 0.1, 0.2)
            guard frame >= 1_600 else { continue }
            observedPhases.insert(Int(output.phase.rawValue))
            XCTAssertEqual(output.noiseRatio, originalSevenNoise,
                           "New 10/10 must preserve the original 7/7 noise level throughout events")
            XCTAssertEqual(output.musicGain, Float(1).addingProduct(-originalSevenMusicLoss, output.envelope),
                           accuracy: 0.0000001)
            if output.phase == RadioInterferencePhaseHold {
                XCTAssertEqual(output.musicGain, 1 - originalSevenMusicLoss)
            }
        }
        XCTAssertEqual(observedPhases, Set([
            RadioInterferencePhaseIdle, RadioInterferencePhaseAttack,
            RadioInterferencePhaseHold, RadioInterferencePhaseRelease
        ].map { Int($0.rawValue) }))
    }

    func testLoweringOnlyBackgroundKeepsMainPeakAndEventClock() throws {
        let changed = try XCTUnwrap(RadioInterferenceCreate(rate, 42))
        let unchanged = try XCTUnwrap(RadioInterferenceCreate(rate, 42))
        defer { RadioInterferenceDestroy(changed); RadioInterferenceDestroy(unchanged) }
        var observedChangedBed = false
        var observedPeak = false
        for frame in 0..<104_000 {
            let background: Float = frame < 8_000 ? 4 : 0
            let a = RadioInterferenceNextFrame(changed, 10, background, true, 0.1, 0.2)
            let b = RadioInterferenceNextFrame(unchanged, 10, 4, true, 0.1, 0.2)
            XCTAssertEqual(a.phase, b.phase)
            XCTAssertEqual(a.eventStarted, b.eventStarted)
            XCTAssertEqual(a.envelope, b.envelope)
            if frame >= 9_600, a.phase == RadioInterferencePhaseIdle {
                observedChangedBed = true
                XCTAssertEqual(a.noiseRatio, 0)
                XCTAssertEqual(b.noiseRatio, 0.36, accuracy: 0.000001)
            }
            if a.phase == RadioInterferencePhaseHold {
                observedPeak = true
                XCTAssertEqual(a.noiseRatio, 0.675, accuracy: 0.000001)
                XCTAssertEqual(a.noiseRatio, b.noiseRatio, accuracy: 0.000001)
            }
        }
        XCTAssertTrue(observedChangedBed)
        XCTAssertTrue(observedPeak)
    }

    func testTransportCancelClearsThePreviousMusicReferenceImmediately() throws {
        let generator = try XCTUnwrap(RadioInterferenceCreate(rate, 17))
        defer { RadioInterferenceDestroy(generator) }
        RadioInterferenceSetNoiseRMS(generator, 0.1)
        var before = RadioInterferenceNextFrame(generator, 10, 2, false, 0.1, 0.2)
        for _ in 0..<8_000 { before = RadioInterferenceNextFrame(generator, 10, 2, false, 0.1, 0.2) }
        XCTAssertGreaterThan(before.noiseSample, 0)

        RadioInterferenceCancel(generator)

        for _ in 0..<1_600 {
            let stopped = RadioInterferenceNextFrame(generator, 10, 2, false, 0.1, 0)
            XCTAssertEqual(stopped.noiseSample, 0, "Stop must not leak the previous source RMS into the new silent source")
            XCTAssertEqual(stopped.musicGain, 1)
            XCTAssertEqual(stopped.noiseRatio, 0.24, accuracy: 0.000001)
        }
    }

    func testInvalidControlsAndRatesStayFinite() throws {
        XCTAssertNil(RadioInterferenceCreate(.nan, 0))
        XCTAssertNil(RadioInterferenceCreate(7_999, 0))
        for rate in [8_000.0, 48_000.0, 384_000.0] {
            let generator = try XCTUnwrap(RadioInterferenceCreate(rate, 0))
            defer { RadioInterferenceDestroy(generator) }
            for _ in 0..<8_000 {
                let output = RadioInterferenceNextFrame(generator, .nan, .nan, true, .infinity, -.infinity)
                XCTAssertEqual(output.musicGain, 1)
                XCTAssertEqual(output.noiseSample, 0)
            }
        }
    }

    func testSourceSilenceGateFadesNoiseInsteadOfCuttingOneSample() throws {
        let generator = try XCTUnwrap(RadioInterferenceCreate(rate, 17))
        defer { RadioInterferenceDestroy(generator) }
        var output = RadioInterferenceNextFrame(generator, 10, 2, true, 0.1, 0.2)
        for _ in 0..<104_000 {
            if output.phase == RadioInterferencePhaseHold { break }
            output = RadioInterferenceNextFrame(generator, 10, 2, true, 0.1, 0.2)
        }
        XCTAssertEqual(output.phase, RadioInterferencePhaseHold)
        let before = output.noiseSample
        output = RadioInterferenceNextFrame(generator, 10, 2, false, 0.1, 0)
        XCTAssertGreaterThan(output.noiseSample, before * 0.96)
        XCTAssertLessThan(output.noiseSample, before)
        var previous = output.noiseSample
        for _ in 0..<800 {
            output = RadioInterferenceNextFrame(generator, 10, 2, false, 0.1, 0)
            XCTAssertLessThanOrEqual(output.noiseSample, previous)
            previous = output.noiseSample
        }
        XCTAssertEqual(output.noiseSample, 0)
    }

    func testFixedRecordingRMSPreservesBurstCrestAndQuietGaps() throws {
        let generator = try XCTUnwrap(RadioInterferenceCreate(rate, 17))
        defer { RadioInterferenceDestroy(generator) }
        RadioInterferenceSetNoiseRMS(generator, 0.0362012984)
        for _ in 0..<16_000 {
            let quiet = RadioInterferenceNextFrame(generator, 0, 0, false, 0.001, 0)
            XCTAssertEqual(quiet.normalizedNoise, 0.001 / 0.0362012984, accuracy: 0.000001)
        }
        let burst = RadioInterferenceNextFrame(generator, 0, 0, false, 0.316035748, 0)
        XCTAssertEqual(burst.normalizedNoise, 0.316035748 / 0.0362012984, accuracy: 0.000001)
        XCTAssertGreaterThan(burst.normalizedNoise, 8, "Reference bursts must not hit the procedural ±3 clamp")
        RadioInterferenceReset(generator, 17)
        let afterReset = RadioInterferenceNextFrame(generator, 0, 0, false, 0.316035748, 0)
        XCTAssertEqual(afterReset.normalizedNoise, burst.normalizedNoise)
        RadioInterferenceSetNoiseRMS(generator, 0)
        XCTAssertLessThanOrEqual(RadioInterferenceNextFrame(generator, 0, 0, false, 1, 0).normalizedNoise, 3)
    }

    func testInvalidFixedCalibrationRemainsBounded() throws {
        let generator = try XCTUnwrap(RadioInterferenceCreate(rate, 17))
        defer { RadioInterferenceDestroy(generator) }
        for rms in [Float.nan, .infinity, -1, 0, Float.leastNonzeroMagnitude] {
            RadioInterferenceSetNoiseRMS(generator, rms)
            let sample = RadioInterferenceNextFrame(generator, 10, 2, true, 1, 0.2)
            XCTAssertTrue(sample.normalizedNoise.isFinite)
            XCTAssertLessThanOrEqual(abs(sample.normalizedNoise), 32)
        }
    }
}
