import Foundation

/// Candidate containers for the AVAudioFile-based playback engine.
/// The extension alone never establishes that a file contains playable audio.
public enum SupportedAudioFormats {
    public static let fileExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "wave", "aif", "aiff", "aifc", "flac", "alac", "caf"
    ]

    public static func contains(_ url: URL) -> Bool {
        fileExtensions.contains(url.pathExtension.lowercased())
    }
}
