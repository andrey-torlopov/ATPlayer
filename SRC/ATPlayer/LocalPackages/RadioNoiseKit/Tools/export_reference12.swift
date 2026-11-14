import Foundation
import RadioNoiseAssets

// Link this validation utility against the package's built RadioNoiseAssets
// library and point PACKAGE_RESOURCE_BUNDLE_PATH at its Products directory.
// It exports the exact production loader output for independent mix/loop analysis.
guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: export_reference12 /absolute/path/balanced12-48k.f32")
}
let sample = try RadioNoiseAssets.loadReference12(sampleRate: 48_000, balanced: true)
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let bytes = sample.samples.withUnsafeBytes { Data($0) }
try bytes.write(to: destination, options: .atomic)
let peak = sample.samples.map(abs).max() ?? 0
let metadata: [String: Any] = [
    "sampleRate": sample.sampleRate,
    "frames": sample.samples.count,
    "durationSeconds": Double(sample.samples.count) / sample.sampleRate,
    "rms": sample.rms,
    "samplePeak": peak,
    "encoding": "mono Float32 little-endian PCM",
    "preparation": "RadioNoiseAssets.loadReference12(sampleRate: 48000, balanced: true)"
]
let json = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
try json.write(to: destination.deletingPathExtension().appendingPathExtension("json"), options: .atomic)
print(String(decoding: json, as: UTF8.self))
