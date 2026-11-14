import RadioNoiseAssets
import XCTest

final class RadioNoiseAssetsTests: XCTestCase {
    func testBundledRecordingDecodesCompleteOriginalPCM() throws {
        let sample = try RadioNoiseAssets.loadReference12(sampleRate: 48_000)
        XCTAssertEqual(sample.sampleRate, 48_000)
        XCTAssertEqual(sample.samples.count, 2_706_726)
        XCTAssertEqual(sample.rms, 0.0362012984, accuracy: 0.00000001)
        XCTAssertEqual(sample.samples.map(abs).max(), 0.316035748)
        // These measurements include all 56.39 seconds, so a short first read
        // or an inadvertently normalized/filtered resource cannot satisfy them.
        XCTAssertTrue(sample.samples.allSatisfy(\.isFinite))
    }

    func testOfflineConversionPreservesDurationAndLevelAtOutputRates() throws {
        for rate in [44_100.0, 96_000.0] {
            let sample = try RadioNoiseAssets.loadReference12(sampleRate: rate)
            XCTAssertEqual(sample.sampleRate, rate)
            XCTAssertEqual(Double(sample.samples.count) / rate, 56.390125, accuracy: 0.001)
            XCTAssertEqual(sample.rms, 0.0362012984, accuracy: 0.001)
            XCTAssertTrue(sample.samples.allSatisfy(\.isFinite))
        }
    }

    func testInvalidOutputRateIsRejectedBeforeReading() {
        for rate in [Double.nan, .infinity, 7_999, 384_001] {
            XCTAssertThrowsError(try RadioNoiseAssets.loadReference12(sampleRate: rate))
        }
    }

    func testBalancedRecordingHasContinuousBoundedEnergyIncludingLoopBoundary() throws {
        let raw = try RadioNoiseAssets.loadReference12(sampleRate: 48_000)
        let balanced = try RadioNoiseAssets.loadReference12(sampleRate: 48_000, balanced: true)
        XCTAssertEqual(balanced.sampleRate, raw.sampleRate)
        XCTAssertLessThan(balanced.samples.count, raw.samples.count, "Only the optional balanced variant omits recorded dead air")
        XCTAssertGreaterThan(Double(balanced.samples.count) / balanced.sampleRate, 53)
        XCTAssertEqual(balanced.rms, 0.03, accuracy: 0.0000001)
        XCTAssertTrue(balanced.samples.allSatisfy(\.isFinite))
        XCTAssertLessThan(balanced.samples.map(abs).max() ?? 1, 0.11)

        // Overlapping circular windows include the final/first source boundary.
        // RMS = sqrt(sum(sample[i]^2) / windowFrameCount).
        for milliseconds in [50, 100] {
            let count = milliseconds * 48
            let rawRMS = circularWindowRMS(raw.samples, frames: count)
            let preparedRMS = circularWindowRMS(balanced.samples, frames: count)
            let low = try XCTUnwrap(preparedRMS.min())
            let high = try XCTUnwrap(preparedRMS.max())
            XCTAssertGreaterThan(low, balanced.rms * 0.85, "Prepared noise must not vanish during recorded gaps")
            XCTAssertLessThan(high, balanced.rms * 1.15)
            XCTAssertLessThan(high / low, 1.36, "The prepared recording must have stable perceived level")
            XCTAssertLessThan(high - low, (rawRMS.max() ?? 0) - (rawRMS.min() ?? 0))
            print("balanced_reference12 window_ms=\(milliseconds) min_rms=\(low) max_rms=\(high) ratio=\(high / low)")
        }
    }

    func testBalancedConversionIsDeterministicAndPreservesPreparedDuration() throws {
        let first = try RadioNoiseAssets.loadReference12(sampleRate: 44_100, balanced: true)
        let second = try RadioNoiseAssets.loadReference12(sampleRate: 44_100, balanced: true)
        XCTAssertEqual(first.samples, second.samples)
        XCTAssertEqual(first.rms, 0.03, accuracy: 0.001)
        XCTAssertEqual(Double(first.samples.count) / first.sampleRate, 53.9, accuracy: 0.001)
    }

    private func circularWindowRMS(_ samples: [Float], frames: Int) -> [Float] {
        stride(from: 0, to: samples.count, by: frames / 4).map { start in
            var sum = 0.0
            for offset in 0..<frames {
                let sample = Double(samples[(start + offset) % samples.count])
                sum += sample * sample
            }
            return Float(sqrt(sum / Double(frames)))
        }
    }
}
