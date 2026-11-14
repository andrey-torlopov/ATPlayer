import Foundation

public struct PlaybackSnapshot: Equatable, Sendable {
    public let trackID: UUID
    public let title: String
    public let artist: String
    public let duration: TimeInterval
    public let currentTime: TimeInterval
    public let isPlaying: Bool
    public let advancesTrackTime: Bool
    public let canPlayPrevious: Bool
    public let canPlayNext: Bool

    public init(trackID: UUID, title: String, artist: String, duration: TimeInterval,
                currentTime: TimeInterval, isPlaying: Bool, canPlayPrevious: Bool, canPlayNext: Bool,
                advancesTrackTime: Bool? = nil) {
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.duration = duration
        self.currentTime = currentTime
        self.isPlaying = isPlaying
        self.advancesTrackTime = advancesTrackTime ?? isPlaying
        self.canPlayPrevious = canPlayPrevious
        self.canPlayNext = canPlayNext
    }
}

public enum PlaybackCommand: Sendable {
    case play
    case pause
    case toggle
    case previous
    case next
    case seek(TimeInterval)
}

@MainActor
public protocol NowPlayingPresenting: AnyObject {
    var handleCommand: (@MainActor @Sendable (PlaybackCommand) -> Void)? { get set }
    func update(_ snapshot: PlaybackSnapshot, force: Bool)
    func clear()
}

@MainActor
public protocol ActivityPresenting: AnyObject {
    func endAllStaleActivities()
    func synchronize(_ snapshot: PlaybackSnapshot, playbackStartDate: Date, allowStart: Bool, force: Bool)
    func retryWhenForegrounded()
    func endActivity()
}
