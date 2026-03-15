import ActivityKit
import Foundation

struct ATPlayerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let trackTitle: String
        let artistName: String
        let duration: TimeInterval
        let currentTime: TimeInterval
        let isPlaying: Bool
    }
}
