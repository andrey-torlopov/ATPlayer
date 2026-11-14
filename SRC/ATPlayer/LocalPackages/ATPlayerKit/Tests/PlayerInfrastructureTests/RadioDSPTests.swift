import AVFoundation
import RadioDSP
import XCTest
@testable import PlayerInfrastructure

final class RadioDSPTests: XCTestCase {
    private let rate = 48_000.0

    private func makeDSP(channels: UInt32 = 2, seed: UInt64 = 17) throws -> OpaquePointer {
        try XCTUnwrap(RadioDSPCreate(rate, channels, seed))
    }

    private func process(_ dsp: OpaquePointer, left: inout [Float], right: inout [Float], time: Int64 = 0) -> Bool {
        let count = UInt32(left.count)
        return left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                RadioDSPProcess(dsp, l.baseAddress, r.baseAddress, count, time)
            }
        }
    }

    func testBypassIsExactWithDeclaredLatency() throws {
        let dsp = try makeDSP()
        defer { RadioDSPDestroy(dsp) }
        RadioDSPSetTransport(dsp, true)
        let input = (0..<4_096).map { Float(sin(Double($0) * 0.3)) * 1.2 }
        var left = input
        var right = input.map { -$0 }
        _ = process(dsp, left: &left, right: &right)
        let delay = Int(RadioDSPLatencyFrames())
        XCTAssertTrue(left.prefix(delay).allSatisfy { $0 == 0 })
        for i in delay..<left.count {
            XCTAssertEqual(left[i], input[i - delay])
            XCTAssertEqual(right[i], -input[i - delay])
        }
        XCTAssertEqual(RadioDSPCurrentPhase(dsp), RadioDSPPhaseBypassed)
        XCTAssertEqual(RadioDSPInterferenceCount(dsp), 0)
    }

    func testTransportGateSilencesMusicAndRadioBedImmediately() throws {
        let dsp = try makeDSP()
        defer { RadioDSPDestroy(dsp) }
        RadioDSPSetSettings(dsp, 10, 10)
        RadioDSPSetTransport(dsp, true)
        var left = [Float](repeating: 0.2, count: 24_000)
        var right = left
        XCTAssertFalse(process(dsp, left: &left, right: &right))
        RadioDSPSetTransport(dsp, false)
        left = [Float](repeating: 0.5, count: 1_024)
        right = left
        XCTAssertTrue(process(dsp, left: &left, right: &right, time: 24_000))
        XCTAssertTrue(left.allSatisfy { $0 == 0 })
        XCTAssertTrue(right.allSatisfy { $0 == 0 })
    }

    func testStopThenPlayBeforeNextRenderCannotLeakBufferedAudioOrNoise() throws {
        for effect in [0, 10] {
            let dsp = try makeDSP()
            defer { RadioDSPDestroy(dsp) }
            let constantNoise = [Float](repeating: 0.03, count: 48_000)
            XCTAssertTrue(constantNoise.withUnsafeBufferPointer {
                RadioDSPSetReferenceSample(dsp, $0.baseAddress, UInt64($0.count))
            })
            RadioDSPSetSettings(dsp, Int32(effect), Int32(effect))
            RadioDSPSetTransport(dsp, true)
            var left = [Float](repeating: 0.2, count: 24_000)
            var right = left.map { -$0 }
            _ = process(dsp, left: &left, right: &right)
            RadioDSPSetTransport(dsp, false)
            RadioDSPSetTransport(dsp, true)
            left = [Float](repeating: 0, count: 48_000)
            right = left
            let silent = process(dsp, left: &left, right: &right, time: 24_000)
            if effect == 0 {
                XCTAssertTrue(silent)
                XCTAssertTrue(left.allSatisfy { $0 == 0 })
                XCTAssertTrue(right.allSatisfy { $0 == 0 })
            } else {
                XCTAssertFalse(silent, "A newly playing silent file has its requested background")
                XCTAssertTrue(left.prefix(Int(RadioDSPLatencyFrames())).allSatisfy { $0 == 0 })
                XCTAssertEqual(left, right, "Old anti-phase music must not survive Stop")
                XCTAssertLessThanOrEqual(left.map(abs).max() ?? 1, 0.02 * 0.675 + 0.000001,
                  "Only the new silent-intro reference may remain, never the old music RMS tail")
            }
            XCTAssertEqual(RadioDSPInterferenceCount(dsp), 0)
        }
    }

    func testFixedSeedIsIndependentOfBufferPartition() throws {
        let a = try XCTUnwrap(RadioDSPCreate(8_000, 2, 71))
        let b = try XCTUnwrap(RadioDSPCreate(8_000, 2, 71))
        defer { RadioDSPDestroy(a); RadioDSPDestroy(b) }
        for dsp in [a, b] {
            RadioDSPSetSettings(dsp, 10, 10)
            RadioDSPSetTransport(dsp, true)
        }
        let input = (0..<96_000).map { Float(sin(Double($0) * 0.031)) * 0.2 }
        var wholeL = input
        var wholeR = input
        _ = process(a, left: &wholeL, right: &wholeR)
        var splitL: [Float] = []
        var splitR: [Float] = []
        for start in stride(from: 0, to: input.count, by: 127) {
            let end = min(input.count, start + 127)
            var l = Array(input[start..<end])
            var r = l
            _ = process(b, left: &l, right: &r, time: Int64(start))
            splitL += l
            splitR += r
        }
        XCTAssertEqual(wholeL, splitL)
        XCTAssertEqual(wholeR, splitR)
        XCTAssertGreaterThan(RadioDSPInterferenceCount(a), 0, "The partition check must include an absorption event")
    }

    func testSourceGateClosesOnExactFrameWithoutLatency() throws {
        let dsp = try makeDSP()
        defer { RadioDSPDestroy(dsp) }
        RadioDSPSetSourceGate(dsp, 73)
        var left = [Float](repeating: 0.5, count: 128)
        var right = left
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                XCTAssertFalse(RadioDSPProcessSourceGate(dsp, l.baseAddress, r.baseAddress, 128, 0))
            }
        }
        XCTAssertEqual(Array(left.prefix(73)), [Float](repeating: 0.5, count: 73))
        XCTAssertTrue(left.dropFirst(73).allSatisfy { $0 == 0 })
        XCTAssertEqual(left, right)
    }

    func testRandomEventsAreDisabledForSilenceAndDry() throws {
        for effect in [0, 10] {
            let dsp = try makeDSP()
            defer { RadioDSPDestroy(dsp) }
            RadioDSPSetTransport(dsp, true)
            RadioDSPSetSettings(dsp, Int32(effect), 0)
            RadioDSPResetReception(dsp, 120)
            for block in 0..<1_000 {
                var left = [Float](repeating: 0, count: 4_096)
                var right = left
                _ = process(dsp, left: &left, right: &right, time: Int64(block * 4_096))
                XCTAssertTrue(left.allSatisfy { $0 == 0 })
            }
            XCTAssertEqual(RadioDSPInterferenceCount(dsp), 0)
        }
    }

    func testRejectsUnsupportedFormats() {
        XCTAssertNil(RadioDSPCreate(.nan, 2, 1))
        XCTAssertNil(RadioDSPCreate(48_000, 0, 1))
        XCTAssertNil(RadioDSPCreate(48_000, 8, 1))
    }

    func testReferenceSampleInstallationRejectsInvalidPCMWithoutDiscardingValidSource() throws {
        let dsp = try makeDSP()
        defer { RadioDSPDestroy(dsp) }
        XCTAssertFalse(RadioDSPHasReferenceSample(dsp))
        XCTAssertFalse(RadioDSPSetReferenceSample(dsp, nil, 0))
        let pcm = (0..<4_096).map { Float(sin(Double($0) * 0.1)) * 0.1 }
        XCTAssertTrue(pcm.withUnsafeBufferPointer {
            RadioDSPSetReferenceSample(dsp, $0.baseAddress, UInt64($0.count))
        })
        XCTAssertTrue(RadioDSPHasReferenceSample(dsp))
        let silence = [Float](repeating: 0, count: 4_096)
        XCTAssertFalse(silence.withUnsafeBufferPointer {
            RadioDSPSetReferenceSample(dsp, $0.baseAddress, UInt64($0.count))
        })
        XCTAssertTrue(RadioDSPHasReferenceSample(dsp))
    }

    func testLimiterProtectsWholeMixtureAtEveryPositiveIntensity() throws {
        for level in [1, 5, 10] {
            let dsp = try makeDSP()
            defer { RadioDSPDestroy(dsp) }
            RadioDSPSetSettings(dsp, Int32(level), Int32(level))
            RadioDSPSetTransport(dsp, true)
            var left = (0..<48_000).map { Float(sin(Double($0) * 0.31)) * 1.7 }
            var right = left.map { -$0 }
            _ = process(dsp, left: &left, right: &right)
            // The initial dry-to-wet ramp deliberately preserves continuity of
            // already-overloaded dry input; the steady wet mixture is protected.
            XCTAssertLessThanOrEqual(left.dropFirst(14_400).map(abs).max() ?? 2, 0.85)
            XCTAssertTrue(left.allSatisfy(\.isFinite))
            XCTAssertTrue(right.allSatisfy(\.isFinite))
        }
    }

    func testInterferenceAbsorbsMusicAtRequestedDepthAndReturnsToUnattenuatedMusicWithNoiseBed() throws {
        let sampleRate = 8_000.0
        let levels: [Int32] = [1, 2, 5, 8, 10]
        let expectedGains = [0.895, 0.83, 0.6875, 0.53, 0.425]
        var firstEventCounts: [UInt64] = []
        for (level, expectedGain) in zip(levels, expectedGains) {
            let dsp = try XCTUnwrap(RadioDSPCreate(sampleRate, 2, 71))
            defer { RadioDSPDestroy(dsp) }
            RadioDSPSetSettings(dsp, level, level)
            RadioDSPSetTransport(dsp, true)
            RadioDSPResetReception(dsp, 120)
            let input = (0..<120_000).map { Float(sin(2 * .pi * 397 * Double($0) / sampleRate)) * 0.08 }
            var left = input
            var right = input.map { -$0 }
            _ = process(dsp, left: &left, right: &right)
            let delay = Int(RadioDSPLatencyFrames())
            var minimumGain = 1.0
            var plateauNoiseEnergy = 0.0
            var plateauMusicEnergy = 0.0
            var plateauFrames = 0
            for i in (delay + 8_000)..<input.count {
                let original = Double(input[i - delay])
                guard abs(original) > 0.005 else { continue }
                let music = (Double(left[i]) - Double(right[i])) / 2
                let noise = (Double(left[i]) + Double(right[i])) / 2
                let gain = music / original
                minimumGain = min(minimumGain, gain)
                if abs(gain - expectedGain) < 0.0001 {
                    plateauNoiseEnergy += noise * noise
                    plateauMusicEnergy += music * music
                    plateauFrames += 1
                }
            }
            XCTAssertEqual(minimumGain, expectedGain, accuracy: 0.0001)
            XCTAssertGreaterThan(plateauFrames, 7_000)
            if level == 10 { XCTAssertGreaterThan(plateauNoiseEnergy, plateauMusicEnergy, "Noise must dominate remaining music during plateau") }
            for interval in [8_000..<16_000, 112_000..<120_000] {
                var bedEnergy = 0.0
                for i in interval {
                    let music = (left[i] - right[i]) / 2
                    let noise = (Double(left[i]) + Double(right[i])) / 2
                    XCTAssertEqual(music, input[i - delay], accuracy: 0.000001,
                                   "Music must retain/recover its original level between absorption events")
                    bedEnergy += noise * noise
                }
                XCTAssertGreaterThan(bedEnergy, 0.000001, "Every positive level retains a quiet noise bed between events")
            }
            firstEventCounts.append(RadioDSPInterferenceCount(dsp))
        }
        XCTAssertEqual(firstEventCounts, [1, 1, 1, 1, 1], "Depth must not change event cadence")
    }

    func testDisablingDuringAbsorptionReturnsToExactDelayedBypass() throws {
        let sampleRate = 8_000.0
        let dsp = try XCTUnwrap(RadioDSPCreate(sampleRate, 2, 71))
        defer { RadioDSPDestroy(dsp) }
        RadioDSPSetSettings(dsp, 10, 10)
        RadioDSPSetTransport(dsp, true)
        var time: Int64 = 0
        repeat {
            var left = [Float](repeating: 0.05, count: 80)
            var right = left.map { -$0 }
            _ = process(dsp, left: &left, right: &right, time: time)
            time += 80
        } while RadioDSPCurrentPhase(dsp) != RadioDSPPhaseInterference && time < 56_000
        XCTAssertEqual(RadioDSPCurrentPhase(dsp), RadioDSPPhaseInterference)
        RadioDSPSetSettings(dsp, 0, 0)
        var left = [Float](repeating: 0.05, count: 8_000)
        var right = left.map { -$0 }
        _ = process(dsp, left: &left, right: &right, time: time)
        XCTAssertTrue(left.suffix(4_000).allSatisfy { $0 == 0.05 })
        XCTAssertTrue(right.suffix(4_000).allSatisfy { $0 == -0.05 })
        XCTAssertEqual(RadioDSPCurrentPhase(dsp), RadioDSPPhaseBypassed)
        RadioDSPSetSettings(dsp, 10, 10)
        left = [Float](repeating: 0.05, count: 16_000)
        right = left.map { -$0 }
        _ = process(dsp, left: &left, right: &right, time: time + 8_000)
        var bedEnergy = 0.0
        for frame in 8_000..<16_000 {
            XCTAssertEqual((left[frame] - right[frame]) / 2, 0.05, accuracy: 0.000001,
                           "Re-enable must wait for a new event rather than revive the old plateau")
            let noise = (Double(left[frame]) + Double(right[frame])) / 2
            bedEnergy += noise * noise
        }
        XCTAssertGreaterThan(bedEnergy, 0.000001, "The positive level restores its quiet noise bed immediately")
        XCTAssertEqual(RadioDSPCurrentPhase(dsp), RadioDSPPhaseReceiving)
    }

    func testBackgroundChangesBedWithoutChangingMusicOrEventPeak() throws {
        let withoutBed = try XCTUnwrap(RadioDSPCreate(8_000, 2, 71))
        let withBed = try XCTUnwrap(RadioDSPCreate(8_000, 2, 71))
        defer { RadioDSPDestroy(withoutBed); RadioDSPDestroy(withBed) }
        RadioDSPSetSettings(withoutBed, 10, 0)
        RadioDSPSetSettings(withBed, 10, 7)
        for dsp in [withoutBed, withBed] {
            RadioDSPSetTransport(dsp, true)
            RadioDSPResetReception(dsp, 120)
        }
        let input = (0..<120_000).map { Float(sin(2 * .pi * 397 * Double($0) / 8_000)) * 0.08 }
        var dryL = input
        var dryR = input.map { -$0 }
        var bedL = dryL
        var bedR = dryR
        _ = process(withoutBed, left: &dryL, right: &dryR)
        _ = process(withBed, left: &bedL, right: &bedR)
        let delay = Int(RadioDSPLatencyFrames())
        var idleEnergy = 0.0
        var plateauFrames = 0
        for index in 8_000..<input.count {
            let dryMusic = (dryL[index] - dryR[index]) / 2
            let bedMusic = (bedL[index] - bedR[index]) / 2
            XCTAssertEqual(dryMusic, bedMusic, accuracy: 0.000001)
            let dryNoise = (dryL[index] + dryR[index]) / 2
            let bedNoise = (bedL[index] + bedR[index]) / 2
            let source = input[index - delay]
            guard abs(source) > 0.005 else { continue }
            let gain = dryMusic / source
            if abs(gain - 1) < 0.000001 {
                XCTAssertEqual(dryNoise, 0, accuracy: 0.000001)
                idleEnergy += Double(bedNoise) * Double(bedNoise)
            }
            if abs(gain - 0.425) < 0.000001 {
                plateauFrames += 1
                XCTAssertEqual(dryNoise, bedNoise, accuracy: 0.000001)
            }
        }
        XCTAssertGreaterThan(idleEnergy, 0.001)
        XCTAssertGreaterThan(plateauFrames, 7_000)
    }

    func testNewTrackDurationPreservesOngoingRadioEnvelope() throws {
        let baseline = try XCTUnwrap(RadioDSPCreate(8_000, 2, 71))
        let nextTrack = try XCTUnwrap(RadioDSPCreate(8_000, 2, 71))
        defer { RadioDSPDestroy(baseline); RadioDSPDestroy(nextTrack) }
        for dsp in [baseline, nextTrack] {
            RadioDSPSetSettings(dsp, 10, 10)
            RadioDSPResetReception(dsp, 120)
            RadioDSPSetTransport(dsp, true)
        }
        var time: Int64 = 0
        repeat {
            for dsp in [baseline, nextTrack] {
                var left = [Float](repeating: 0.05, count: 80)
                var right = left.map { -$0 }
                _ = process(dsp, left: &left, right: &right, time: time)
            }
            time += 80
        } while RadioDSPCurrentPhase(baseline) != RadioDSPPhaseInterference && time < 56_000
        XCTAssertEqual(RadioDSPCurrentPhase(baseline), RadioDSPPhaseInterference)
        RadioDSPResetReception(nextTrack, 180)
        var baselineL = [Float](repeating: 0.05, count: 8_000)
        var baselineR = baselineL.map { -$0 }
        var nextL = baselineL
        var nextR = baselineR
        _ = process(baseline, left: &baselineL, right: &baselineR, time: time)
        _ = process(nextTrack, left: &nextL, right: &nextR, time: time)
        XCTAssertEqual(nextL, baselineL, "Updating track duration must not reset the active radio event")
        XCTAssertEqual(nextR, baselineR)
    }

    func testPositiveBackgroundRetainsMusicReferenceDuringSilentPassage() throws {
        let dsp = try XCTUnwrap(RadioDSPCreate(8_000, 2, 71))
        defer { RadioDSPDestroy(dsp) }
        let recording = [Float](repeating: 0.03, count: 8_000)
        XCTAssertTrue(recording.withUnsafeBufferPointer {
            RadioDSPSetReferenceSample(dsp, $0.baseAddress, UInt64($0.count))
        })
        RadioDSPSetSettings(dsp, 10, 10)
        RadioDSPSetTransport(dsp, true)
        var left = [Float](repeating: 0.05, count: 16_000)
        var right = left.map { -$0 }
        _ = process(dsp, left: &left, right: &right)
        let lastNoise = (left.last! + right.last!) / 2
        left = [Float](repeating: 0, count: 48_000)
        right = left
        _ = process(dsp, left: &left, right: &right, time: 16_000)
        XCTAssertGreaterThan(left.suffix(8_000).min() ?? 0, lastNoise * 0.8,
                             "The ongoing bed must retain the measured music level instead of fading or falling back to the intro floor")
        // The first declared-latency frames still contain the preceding music.
        let delay = Int(RadioDSPLatencyFrames())
        let maximumChannelDifference = zip(left.dropFirst(delay), right.dropFirst(delay))
            .reduce(Float(0)) { max($0, abs($1.0 - $1.1)) }
        XCTAssertEqual(maximumChannelDifference, 0, accuracy: 0.000001)
        XCTAssertEqual(RadioDSPInterferenceCount(dsp), 0,
                       "A silent passage keeps its background but must not start new random events")
    }

    func testZeroBackgroundInterferenceFadesDuringSilentPassage() throws {
        let dsp = try makeDSP(seed: 20261114)
        defer { RadioDSPDestroy(dsp) }
        RadioDSPSetSettings(dsp, 10, 0)
        RadioDSPSetTransport(dsp, true)
        var left = (0..<48_000).map { Float(sin(Double($0) * 0.1)) * 0.2 }
        var right = left
        _ = process(dsp, left: &left, right: &right)
        left = [Float](repeating: 0, count: 96_000)
        right = left
        _ = process(dsp, left: &left, right: &right, time: 48_000)
        XCTAssertTrue(left.suffix(48_000).allSatisfy { abs($0) < 0.000001 })
        XCTAssertTrue(right.suffix(48_000).allSatisfy { abs($0) < 0.000001 })
    }

    func testMonoAndStereoStayFiniteAcrossSampleRatesAndInputShapes() throws {
        for sampleRate in [44_100.0, 48_000.0, 96_000.0] {
            for channelCount in [UInt32(1), UInt32(2)] {
                let dsp = try XCTUnwrap(RadioDSPCreate(sampleRate, channelCount, 19))
                defer { RadioDSPDestroy(dsp) }
                RadioDSPSetSettings(dsp, 10, 10)
                RadioDSPSetTransport(dsp, true)
                RadioDSPResetReception(dsp, 3)
                let count = Int(sampleRate)
                var left = (0..<count).map { frame -> Float in
                    let time = Double(frame) / sampleRate
                    let chirp = 0.4 * sin(2 * .pi * (30 * time + 7_000 * time * time))
                    return Float(chirp + (frame.isMultiple(of: 4_096) ? 1.0 : 0.0))
                }
                var right = left
                left.withUnsafeMutableBufferPointer { l in
                    right.withUnsafeMutableBufferPointer { r in
                        _ = RadioDSPProcess(dsp, l.baseAddress, channelCount == 2 ? r.baseAddress : nil,
                                            UInt32(count), 0)
                    }
                }
                XCTAssertTrue(left.allSatisfy(\.isFinite))
                XCTAssertLessThan(left.dropFirst(Int(sampleRate * 0.3)).map(abs).max() ?? 2, 0.85)
                XCTAssertEqual(RadioDSPInterferenceCount(dsp), 0, "First three seconds must be event-free")
            }
        }
    }

    func testEventScheduleHasNoPauseDebtAndNoLastTwoSecondEvent() throws {
        let dsp = try makeDSP(seed: 1)
        defer { RadioDSPDestroy(dsp) }
        RadioDSPSetSettings(dsp, 10, 10)
        RadioDSPSetTransport(dsp, true)
        // Initial wait is at least three seconds; the last two seconds forbid a new event.
        RadioDSPResetReception(dsp, 5)
        for block in 0..<250 {
            var left = (0..<960).map { Float(sin(Double(block * 960 + $0) * 0.03)) * 0.1 }
            var right = left
            _ = process(dsp, left: &left, right: &right, time: Int64(block * 960))
        }
        XCTAssertEqual(RadioDSPInterferenceCount(dsp), 0)
        RadioDSPSetTransport(dsp, false)
        var left = [Float](repeating: 0, count: 4_096)
        var right = left
        _ = process(dsp, left: &left, right: &right, time: 240_000)
        RadioDSPResetReception(dsp, 120)
        RadioDSPSetTransport(dsp, true)
        // A large host-time jump after suspension must not create catch-up events.
        for block in 0..<150 {
            left = (0..<960).map { Float(sin(Double(block * 960 + $0) * 0.03)) * 0.1 }
            right = left
            _ = process(dsp, left: &left, right: &right, time: 100_000_000 + Int64(block * 960))
        }
        XCTAssertEqual(RadioDSPInterferenceCount(dsp), 0)
    }

    @MainActor
    func testActualAudioUnitPlaysBackgroundThroughSilenceAndStopsExactly() async throws {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let node = try await RadioAudioUnit.makeAVAudioUnit()
        let radio = try XCTUnwrap(node.auAudioUnit as? RadioAudioUnit)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        engine.attach(player)
        engine.attach(node)
        engine.connect(player, to: node, format: format)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1_024)
        let silence = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000))
        silence.frameLength = silence.frameCapacity
        for channel in 0..<2 {
            try XCTUnwrap(silence.floatChannelData?[channel]).update(repeating: 0, count: 96_000)
        }
        player.scheduleBuffer(silence, completionHandler: nil)
        engine.prepare()
        XCTAssertTrue(radio.hasReferenceSample, "The real AU must install the bundled WAV12 before rendering")
        try engine.start()
        defer { engine.stop() }
        radio.apply(effectIntensity: 10, backgroundIntensity: 10)
        radio.setTransport(active: true)
        player.play()
        let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024))
        var peak: Float = 0
        var rendered = 0
        while rendered < 48_000 {
            let status = try engine.renderOffline(1_024, to: output)
            XCTAssertEqual(status, .success)
            guard status == .success else { break }
            let samples = try XCTUnwrap(output.floatChannelData?[0])
            for frame in 0..<Int(output.frameLength) { peak = max(peak, abs(samples[frame])) }
            rendered += Int(output.frameLength)
        }
        XCTAssertGreaterThan(peak, 0.005)
        XCTAssertLessThan(peak, 0.1, "A silent intro uses the conservative 0.02 RMS reference")
        XCTAssertEqual(radio.radioPhase, .receiving)
        XCTAssertGreaterThanOrEqual(radio.renderedSampleTime, 48_000)
        radio.setTransport(active: false)
        XCTAssertEqual(try engine.renderOffline(1_024, to: output), .success)
        for channel in 0..<2 {
            let samples = try XCTUnwrap(output.floatChannelData?[channel])
            XCTAssertTrue((0..<Int(output.frameLength)).allSatisfy { samples[$0] == 0 })
        }
        XCTAssertEqual(radio.radioPhase, .bypassed)
    }

    @MainActor
    func testOfflineABGraphMutesAAndPreservesFirstFrameOfB() async throws {
        let engine = AVAudioEngine()
        let a = AVAudioPlayerNode()
        let b = AVAudioPlayerNode()
        let gateA = try await RadioAudioUnit.makeSourceGate()
        let gateB = try await RadioAudioUnit.makeSourceGate()
        let receiver = try await RadioAudioUnit.makeAVAudioUnit()
        let radio = try XCTUnwrap(receiver.auAudioUnit as? RadioAudioUnit)
        let sourceGate = try XCTUnwrap(gateA.auAudioUnit as? RadioAudioUnit)
        let mixer = AVAudioMixerNode()
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        for node in [a, b, gateA, gateB, receiver, mixer] as [AVAudioNode] { engine.attach(node) }
        engine.connect(a, to: gateA, format: format)
        engine.connect(b, to: gateB, format: format)
        engine.connect(gateA, to: mixer, fromBus: 0, toBus: 0, format: format)
        engine.connect(gateB, to: mixer, fromBus: 0, toBus: 1, format: format)
        engine.connect(mixer, to: receiver, format: format)
        engine.connect(receiver, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 256)
        let bufferA = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000))
        let bufferB = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        bufferA.frameLength = 96_000
        bufferB.frameLength = 48_000
        for channel in 0..<2 {
            // A remains scheduled beyond the switch and the rendered interval.
            // Opposite channels identify its leakage independently of mono noise.
            try XCTUnwrap(bufferA.floatChannelData?[channel])
                .update(repeating: channel == 0 ? 0.05 : -0.05, count: 96_000)
            let samplesB = try XCTUnwrap(bufferB.floatChannelData?[channel])
            samplesB.update(repeating: 0, count: 48_000)
            samplesB[0] = 0.8 // A unique onset: skipping frame zero loses this impulse.
        }
        a.scheduleBuffer(bufferA, completionHandler: nil)
        b.scheduleBuffer(bufferB, completionHandler: nil)
        engine.prepare()
        XCTAssertTrue(radio.hasReferenceSample)
        XCTAssertFalse(sourceGate.hasReferenceSample, "Source gates must not allocate unused recording copies")
        try engine.start()
        defer { engine.stop() }
        radio.apply(effectIntensity: 0, backgroundIntensity: 0)
        radio.setTransport(active: true)
        let switchFrame: Int64 = 24_000
        sourceGate.setSourceGate(closeSampleTime: switchFrame)
        a.play(at: AVAudioTime(sampleTime: 0, atRate: rate))
        b.play(at: AVAudioTime(sampleTime: switchFrame, atRate: rate))
        let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256))
        var mid: [Float] = []
        var side: [Float] = []
        while mid.count < 76_800 {
            let status = try engine.renderOffline(256, to: output)
            XCTAssertEqual(status, .success)
            guard status == .success else { break }
            let left = try XCTUnwrap(output.floatChannelData?[0])
            let right = try XCTUnwrap(output.floatChannelData?[1])
            for frame in 0..<Int(output.frameLength) {
                mid.append((left[frame] + right[frame]) / 2)
                side.append((left[frame] - right[frame]) / 2)
            }
        }
        let onset = Int(switchFrame) + Int(RadioDSPLatencyFrames())
        XCTAssertEqual(mid.count, 76_800)
        guard mid.count > onset + 4_096 else { return }
        XCTAssertEqual(side[512], 0.05, accuracy: 0.000001, "The side probe must detect A before the gate closes")
        XCTAssertEqual(side[onset - 1], 0.05, accuracy: 0.000001,
                       "A must continue through the last frame before the common boundary")
        XCTAssertEqual(mid[onset - 1], 0, accuracy: 0.000001)
        XCTAssertEqual(mid[onset], 0.8, accuracy: 0.000001,
                       "B must begin with its exact first sample at the common boundary")
        XCTAssertLessThan(side[onset..<side.count].map(abs).max() ?? 1, 0.000001,
                          "A must stop on the same frame B begins, with no delayed overlap")
        XCTAssertLessThan(mid[(onset + 1)..<mid.count].map(abs).max() ?? 1, 0.000001)
        XCTAssertEqual(radio.radioPhase, .bypassed)
    }
}
