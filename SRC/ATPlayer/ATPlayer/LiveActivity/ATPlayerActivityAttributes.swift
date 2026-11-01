import ActivityKit
import Foundation

// ActivityKit exchanges these values across executors and with the widget.
nonisolated struct ATPlayerActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        let trackTitle: String
        let artistName: String
        let duration: TimeInterval
        let currentTime: TimeInterval
        let isPlaying: Bool
        let playbackStartDate: Date
    }
}
