import ActivityKit
import Foundation

// ActivityKit exchanges these values across executors and with the widget.
public nonisolated struct ATPlayerActivityAttributes: ActivityAttributes, Sendable {
    public init() {}

    public struct ContentState: Codable, Hashable, Sendable {
        public let trackID: UUID
        public let trackTitle: String
        public let artistName: String
        public let duration: TimeInterval
        public let currentTime: TimeInterval
        public let isPlaying: Bool
        public let playbackStartDate: Date
        public let canPlayPrevious: Bool
        public let canPlayNext: Bool

        public init(trackID: UUID, trackTitle: String, artistName: String, duration: TimeInterval,
                    currentTime: TimeInterval, isPlaying: Bool, playbackStartDate: Date,
                    canPlayPrevious: Bool, canPlayNext: Bool) {
            self.trackID = trackID
            self.trackTitle = trackTitle
            self.artistName = artistName
            self.duration = duration
            self.currentTime = currentTime
            self.isPlaying = isPlaying
            self.playbackStartDate = playbackStartDate
            self.canPlayPrevious = canPlayPrevious
            self.canPlayNext = canPlayNext
        }
    }
}
