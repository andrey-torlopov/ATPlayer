import AVFoundation
import Foundation

/// Immutable, mono Float32 PCM prepared for an output device's sample rate.
public struct RadioNoiseSample: Sendable {
    public let samples: [Float]
    public let sampleRate: Double
    /// Full prepared-clip RMS, used by the mixer for fixed level calibration.
    public let rms: Float
}

public enum RadioNoiseAssetError: LocalizedError {
    case invalidSampleRate
    case missingReference
    case invalidReference
    case conversionFailed

    public var errorDescription: String? {
        switch self {
        case .invalidSampleRate: "Unsupported radio recording sample rate."
        case .missingReference: "The radio reference recording is missing from the resource bundle."
        case .invalidReference: "The radio reference recording could not be decoded completely."
        case .conversionFailed: "The radio reference recording could not be converted to the output sample rate."
        }
    }
}

public enum RadioNoiseAssets {
    /// File I/O, decoding, conversion and allocation occur here. Call only while
    /// creating the audio graph, never from an audio render callback.
    public static func loadReference12(sampleRate: Double, balanced: Bool = false) throws -> RadioNoiseSample {
        guard sampleRate.isFinite, (8_000...384_000).contains(sampleRate) else {
            throw RadioNoiseAssetError.invalidSampleRate
        }
        guard let url = Bundle.module.url(forResource: "Uniden12.mono", withExtension: "wav") else {
            throw RadioNoiseAssetError.missingReference
        }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.processingFormat.channelCount == 1, file.length > 0,
              file.length <= Int64(UInt32.max),
              let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              let chunk = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384),
              let destination = source.floatChannelData?[0] else {
            throw RadioNoiseAssetError.invalidReference
        }
        // AVAudioFile may return a short read; continue until the full file is decoded.
        while source.frameLength < source.frameCapacity {
            let remaining = source.frameCapacity - source.frameLength
            try file.read(into: chunk, frameCount: min(chunk.frameCapacity, remaining))
            guard chunk.frameLength > 0, let input = chunk.floatChannelData?[0] else {
                throw RadioNoiseAssetError.invalidReference
            }
            destination.advanced(by: Int(source.frameLength)).update(from: input, count: Int(chunk.frameLength))
            source.frameLength += chunk.frameLength
        }

        if balanced {
            // Prepare at the recording's native rate, before device conversion.
            // This keeps balancing deterministic and avoids repeated high-rate work.
            let original = Array(UnsafeBufferPointer(start: destination, count: Int(source.frameLength)))
            let prepared = try balancedRecording(original, sampleRate: source.format.sampleRate)
            prepared.withUnsafeBufferPointer {
                destination.update(from: $0.baseAddress!, count: $0.count)
            }
            source.frameLength = AVAudioFrameCount(prepared.count)
        }

        let samples: [Float]
        if sampleRate == source.format.sampleRate {
            samples = Array(UnsafeBufferPointer(start: destination, count: Int(source.frameLength)))
        } else {
            samples = try converted(source, sampleRate: sampleRate)
        }
        guard !samples.isEmpty else { throw RadioNoiseAssetError.invalidReference }
        var sumSquares = 0.0
        for sample in samples {
            guard sample.isFinite else { throw RadioNoiseAssetError.invalidReference }
            sumSquares += Double(sample) * Double(sample)
        }
        // RMS = sqrt(sum(sample[i]^2) / frameCount), without local gain riding.
        let rms = Float(sqrt(sumSquares / Double(samples.count)))
        guard rms > 0 else { throw RadioNoiseAssetError.invalidReference }
        return RadioNoiseSample(samples: samples, sampleRate: sampleRate, rms: rms)
    }

    /// Offline amplitude preparation only: retain the recorded waveform and pitch.
    /// Omit near-silent recording gaps instead of amplifying their digital floor.
    private static func balancedRecording(_ input: [Float], sampleRate: Double) throws -> [Float] {
        let window = max(1, Int(sampleRate * 0.01))
        let splice = max(1, Int(sampleRate * 0.02))
        var ranges: [Range<Int>] = []
        var activeStart: Int?
        for start in stride(from: 0, to: input.count, by: window) {
            let end = min(input.count, start + window)
            var power = 0.0
            for index in start..<end { power += Double(input[index]) * Double(input[index]) }
            let audible = sqrt(power / Double(end - start)) >= 0.005
            if audible && activeStart == nil { activeStart = start }
            if !audible, let active = activeStart {
                ranges.append(active..<start)
                activeStart = nil
            }
        }
        if let activeStart { ranges.append(activeStart..<input.count) }
        guard !ranges.isEmpty else { throw RadioNoiseAssetError.invalidReference }
        var joined: [Float] = []
        joined.reserveCapacity(input.count)
        for detected in ranges {
            // Detection windows may straddle the start/end of true dead air.
            // Keep one 10 ms guard inside each audible span.
            guard detected.count > 2 * window + splice else { continue }
            let range = (detected.lowerBound + window)..<(detected.upperBound - window)
            let overlap = min(splice, joined.count, range.count)
            if overlap > 0 {
                let offset = joined.count - overlap
                for frame in 0..<overlap {
                    let weight = Float(0.5 - 0.5 * cos(.pi * Double(frame) / Double(max(1, overlap - 1))))
                    joined[offset + frame] = joined[offset + frame] * (1 - weight) + input[range.lowerBound + frame] * weight
                }
            }
            joined.append(contentsOf: input[(range.lowerBound + overlap)..<range.upperBound])
        }
        guard !joined.isEmpty else { throw RadioNoiseAssetError.invalidReference }

        // Two bounded, smooth gain passes level the recorded waveform without
        // generating tones. Centered 20 ms RMS anticipates bursts; 10 ms gain
        // smoothing in both directions avoids hard gain boundaries.
        let half = max(1, Int(sampleRate * 0.01))
        let targetRMS = 0.03
        let alpha = 1 - exp(-1 / (0.01 * sampleRate))
        for _ in 0..<2 {
            var power = 0.0
            var lower = 0
            var upper = min(joined.count, half + 1)
            for index in lower..<upper { power += Double(joined[index]) * Double(joined[index]) }
            var gains = [Double](repeating: 0, count: joined.count)
            for index in joined.indices {
                let nextLower = max(0, index - half)
                let nextUpper = min(joined.count, index + half + 1)
                while lower < nextLower { power -= Double(joined[lower]) * Double(joined[lower]); lower += 1 }
                while upper < nextUpper { power += Double(joined[upper]) * Double(joined[upper]); upper += 1 }
                let rms = sqrt(max(0, power) / Double(upper - lower))
                let desired = min(4, max(0.25, targetRMS / max(0.005, rms)))
                gains[index] = index == 0 ? desired : gains[index - 1] + alpha * (desired - gains[index - 1])
            }
            if gains.count > 1 {
                for index in stride(from: gains.count - 2, through: 0, by: -1) {
                    gains[index] = gains[index + 1] + alpha * (gains[index] - gains[index + 1])
                }
            }
            for index in joined.indices { joined[index] *= Float(gains[index]) }
        }

        // Offline peak anticipation controls isolated hits with a 4 ms envelope.
        // The gain reduction approaches each peak from both sides, preserving the
        // waveform instead of clipping samples or introducing a new noise source.
        let ceiling = 0.105
        let decay = exp(-1 / (0.004 * sampleRate))
        var reductions = [Double](repeating: 0, count: joined.count)
        for index in joined.indices {
            let required = max(0, 1 - ceiling / max(ceiling, Double(abs(joined[index]))))
            reductions[index] = max(required, index == 0 ? 0 : reductions[index - 1] * decay)
        }
        if reductions.count > 1 {
            for index in stride(from: reductions.count - 2, through: 0, by: -1) {
                reductions[index] = max(reductions[index], reductions[index + 1] * decay)
            }
        }
        var sumSquares = 0.0
        for index in joined.indices {
            joined[index] *= Float(1 - reductions[index])
            sumSquares += Double(joined[index]) * Double(joined[index])
        }
        let rms = sqrt(sumSquares / Double(joined.count))
        guard rms > 0, rms.isFinite else { throw RadioNoiseAssetError.invalidReference }
        let normalization = Float(targetRMS / rms)
        for index in joined.indices { joined[index] *= normalization }
        return joined
    }

    private static func converted(_ source: AVAudioPCMBuffer, sampleRate: Double) throws -> [Float] {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let converter = AVAudioConverter(from: source.format, to: format),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384) else {
            throw RadioNoiseAssetError.conversionFailed
        }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        var supplied = false
        let expectedCount = Int(ceil(Double(source.frameLength) * sampleRate / source.format.sampleRate))
        var result: [Float] = []
        result.reserveCapacity(expectedCount)
        // Bounded offline drain, including the converter's filter tail.
        for _ in 0..<(expectedCount / Int(output.frameCapacity) + 8) {
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                if supplied {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                supplied = true
                inputStatus.pointee = .haveData
                return source
            }
            if let error { throw error }
            if output.frameLength > 0, let data = output.floatChannelData?[0] {
                result.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
            }
            if status == .endOfStream { return result }
            if status == .error || (output.frameLength == 0 && status != .inputRanDry) {
                throw RadioNoiseAssetError.conversionFailed
            }
        }
        throw RadioNoiseAssetError.conversionFailed
    }
}
