import AppLocalization
import ActivityKit
import Foundation
import OSLog
import PlaybackDomain
import PlaybackActivity

@MainActor
public final class ATPlayerActivityService: ActivityPresenting {
    public init() {}

    private static let logger = Logger(subsystem: "dev.torlopov.atplayer.ios", category: "LiveActivity")
    private static let progressUpdateInterval: TimeInterval = 15
    private var currentActivity: Activity<ATPlayerActivityAttributes>?
    private var lastState: ATPlayerActivityAttributes.ContentState?
    private var lastUpdateDate: Date = .distantPast
    private var operation: Task<Void, Never>?
    private var revision: UInt = 0
    private var dismissedTrackID: UUID?
    private var failedTrackID: UUID?

    public func endAllStaleActivities() {
        // Capture only activities from the previous process, never a newly
        // requested activity from the current playback session.
        let previousActivities = Activity<ATPlayerActivityAttributes>.activities
        operation = Task {
            for activity in previousActivities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    public func synchronize(
        _ snapshot: PlaybackSnapshot,
        playbackStartDate: Date,
        allowStart: Bool,
        force: Bool = false
    ) {
        let state = ATPlayerActivityAttributes.ContentState(
            trackID: snapshot.trackID, trackTitle: snapshot.title, artistName: snapshot.artist,
            duration: snapshot.duration, currentTime: snapshot.currentTime, isPlaying: snapshot.isPlaying,
            playbackStartDate: playbackStartDate, canPlayPrevious: snapshot.canPlayPrevious,
            canPlayNext: snapshot.canPlayNext, languageCode: L10n.languageCode
        )
        let now = Date.now
        if let activity = currentActivity,
           activity.activityState == .dismissed || activity.activityState == .ended {
            currentActivity = nil
            dismissedTrackID = activity.content.state.trackID
        }

        if currentActivity == nil {
            guard allowStart, state.isPlaying,
                  dismissedTrackID != state.trackID, failedTrackID != state.trackID,
                  ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        }

        let changed = lastState.map {
            $0.trackID != state.trackID || $0.trackTitle != state.trackTitle
                || $0.artistName != state.artistName || $0.duration != state.duration
                || $0.isPlaying != state.isPlaying || $0.languageCode != state.languageCode
                || $0.canPlayPrevious != state.canPlayPrevious || $0.canPlayNext != state.canPlayNext
        } ?? true
        let expectedTime = lastState.map {
            $0.currentTime + ($0.isPlaying ? now.timeIntervalSince(lastUpdateDate) : 0)
        } ?? state.currentTime
        let positionChanged = abs(state.currentTime - expectedTime) > 0.5
        guard currentActivity == nil || force || changed || positionChanged
                || now.timeIntervalSince(lastUpdateDate) >= Self.progressUpdateInterval else { return }

        // Paused local playback doesn't expire after an arbitrary 30 seconds.
        // The system timer animates progress between actual state updates.
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity = currentActivity {
            revision &+= 1
            let requestedRevision = revision
            let previousOperation = operation
            operation = Task { [weak self] in
                await previousOperation?.value
                guard let self, self.revision == requestedRevision else { return }
                await activity.update(content)
            }
        } else {
            do {
                currentActivity = try Activity.request(
                    attributes: ATPlayerActivityAttributes(), content: content, pushType: nil
                )
                failedTrackID = nil
            } catch {
                let systemError = error as NSError
                Self.logger.error("Live Activity unavailable: domain=\(systemError.domain, privacy: .public), code=\(systemError.code, privacy: .public)")
                // Avoid retrying every progress tick; audio remains independent.
                failedTrackID = state.trackID
                return
            }
        }
        lastState = state
        lastUpdateDate = now
    }

    public func retryWhenForegrounded() {
        failedTrackID = nil
        lastUpdateDate = .distantPast
    }

    public func endActivity() {
        revision &+= 1
        let activity = currentActivity
        currentActivity = nil
        lastState = nil
        dismissedTrackID = nil
        failedTrackID = nil
        lastUpdateDate = .distantPast
        guard let activity else { return }
        let previousOperation = operation
        operation = Task {
            await previousOperation?.value
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
