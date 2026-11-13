import AVFoundation
import Foundation
import PlaybackDomain

enum AudioFileValidationError: Error {
    case unsupportedFile
    case emptyOrInvalidAudio
}

/// Uses the same decoder as playback. Run on a worker, with file access held by
/// the caller. Reading to EOF catches failures beyond an otherwise valid header.
enum AudioFileValidator {
    static func validate(_ url: URL, checkCancellation: () throws -> Void = {}) throws -> TimeInterval {
        try checkCancellation()
        guard url.isFileURL, SupportedAudioFormats.contains(url) else {
            throw AudioFileValidationError.unsupportedFile
        }
        var resourceURL = url
        resourceURL.removeAllCachedResourceValues()
        let values = try resourceURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0 else {
            throw AudioFileValidationError.emptyOrInvalidAudio
        }
        try validateWaveBounds(url, checkCancellation: checkCancellation)

        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let expectedFrames = file.length
        guard expectedFrames > 0, format.sampleRate.isFinite, format.sampleRate > 0,
              format.channelCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384) else {
            throw AudioFileValidationError.emptyOrInvalidAudio
        }
        var decodedFrames: AVAudioFramePosition = 0
        while decodedFrames < expectedFrames {
            try checkCancellation()
            let remaining = AVAudioFrameCount(min(AVAudioFramePosition(buffer.frameCapacity), expectedFrames - decodedFrames))
            try file.read(into: buffer, frameCount: remaining)
            guard buffer.frameLength > 0 else {
                throw AudioFileValidationError.emptyOrInvalidAudio
            }
            decodedFrames += AVAudioFramePosition(buffer.frameLength)
        }
        try checkCancellation()
        guard decodedFrames > 0, decodedFrames >= expectedFrames else {
            throw AudioFileValidationError.emptyOrInvalidAudio
        }
        return TimeInterval(expectedFrames) / format.sampleRate
    }

    private static func validateWaveBounds(_ url: URL, checkCancellation: () throws -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: 12), header.count == 12,
              header[0..<4].elementsEqual("RIFF".utf8),
              header[8..<12].elementsEqual("WAVE".utf8) else { return }

        func chunkSize(_ bytes: Data.SubSequence) -> UInt64 {
            bytes.reversed().reduce(0) { ($0 << 8) | UInt64($1) }
        }

        // Core Audio clamps truncated WAV payloads to EOF. Verify declared chunk
        // boundaries before trusting the decoder's reported frame count.
        let physicalEnd = try handle.seekToEnd()
        let containerEnd = chunkSize(header[4..<8]) + 8
        guard containerEnd >= 12, containerEnd <= physicalEnd else {
            throw AudioFileValidationError.emptyOrInvalidAudio
        }
        var offset: UInt64 = 12
        while offset < containerEnd {
            try checkCancellation()
            guard containerEnd - offset >= 8 else {
                throw AudioFileValidationError.emptyOrInvalidAudio
            }
            try handle.seek(toOffset: offset)
            guard let chunk = try handle.read(upToCount: 8), chunk.count == 8 else {
                throw AudioFileValidationError.emptyOrInvalidAudio
            }
            let size = chunkSize(chunk[4..<8])
            let paddedSize = size + (size & 1)
            guard paddedSize <= containerEnd - offset - 8 else {
                throw AudioFileValidationError.emptyOrInvalidAudio
            }
            offset += 8 + paddedSize
        }
    }
}
