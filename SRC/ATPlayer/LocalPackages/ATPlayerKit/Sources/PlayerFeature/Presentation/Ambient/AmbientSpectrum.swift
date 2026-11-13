import CoreGraphics
import Foundation

/// Bounded audio samples and frame-rate-independent display smoothing. No generated signal.
struct AmbientSpectrum {
    // Keep the Metal constant ambientSpectrumBandCount in sync with this buffer contract.
    static let bandCount = 72
    private static let attackTime: TimeInterval = 0.065
    private static let releaseTime: TimeInterval = 0.24
    private static let silenceFloor: Float = 0.0001

    private var targets = [Float](repeating: 0, count: AmbientSpectrum.bandCount)
    private(set) var levels = [Float](repeating: 0, count: AmbientSpectrum.bandCount)

    mutating func update(_ values: [CGFloat]) {
        for index in 0..<Self.bandCount {
            guard index < values.count, values[index].isFinite else {
                targets[index] = 0
                continue
            }
            // Clamp before converting CGFloat to Float, including very large finite inputs.
            targets[index] = Float(min(1, max(0, values[index])))
        }
    }

    mutating func advance(by elapsed: TimeInterval) {
        guard elapsed.isFinite, elapsed > 0 else { return }
        let attack = Float(1 - exp(-elapsed / Self.attackTime))
        let release = Float(1 - exp(-elapsed / Self.releaseTime))
        for index in 0..<Self.bandCount {
            let target = targets[index]
            let current = levels[index]
            let blend = target > current ? attack : release
            let value = min(1, max(0, current + (target - current) * blend))
            levels[index] = target == 0 && value < Self.silenceFloor ? 0 : value
        }
    }

    mutating func reset() {
        for index in 0..<Self.bandCount {
            targets[index] = 0
            levels[index] = 0
        }
    }
}
