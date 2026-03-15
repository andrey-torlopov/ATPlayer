import ActivityKit
import Foundation

@MainActor
final class ATPlayerActivityService {
    private var currentActivity: Activity<ATPlayerActivityAttributes>?
    private var lastUpdateTime: Date = .distantPast

    func endAllStaleActivities() {
        let state = ATPlayerActivityAttributes.ContentState(
            trackTitle: "",
            artistName: "",
            duration: 0,
            currentTime: 0,
            isPlaying: false,
            playbackStartDate: Date.now
        )
        let content = ActivityContent(state: state, staleDate: nil)
        for activity in Activity<ATPlayerActivityAttributes>.activities {
            Task {
                await activity.end(content, dismissalPolicy: .immediate)
            }
        }
    }

    func startOrUpdateActivity(
        trackTitle: String,
        artistName: String,
        duration: TimeInterval,
        currentTime: TimeInterval,
        isPlaying: Bool
    ) {
        let state = ATPlayerActivityAttributes.ContentState(
            trackTitle: trackTitle,
            artistName: artistName,
            duration: duration,
            currentTime: currentTime,
            isPlaying: isPlaying,
            playbackStartDate: Date.now.addingTimeInterval(-currentTime)
        )

        let staleDate = Date.now.addingTimeInterval(30)

        if let currentActivity {
            let content = ActivityContent(state: state, staleDate: staleDate)
            Task {
                await currentActivity.update(content)
            }
            return
        }

        let content = ActivityContent(state: state, staleDate: staleDate)
        do {
            currentActivity = try Activity<ATPlayerActivityAttributes>.request(
                attributes: ATPlayerActivityAttributes(),
                content: content,
                pushType: nil
            )
        } catch {
            print("LiveActivity start error: \(error.localizedDescription)")
        }
    }

    func updateActivity(
        trackTitle: String,
        artistName: String,
        duration: TimeInterval,
        currentTime: TimeInterval,
        isPlaying: Bool
    ) {
        guard let currentActivity else { return }

        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= 5.0 else { return }
        lastUpdateTime = now

        let state = ATPlayerActivityAttributes.ContentState(
            trackTitle: trackTitle,
            artistName: artistName,
            duration: duration,
            currentTime: currentTime,
            isPlaying: isPlaying,
            playbackStartDate: Date.now.addingTimeInterval(-currentTime)
        )

        let content = ActivityContent(state: state, staleDate: Date.now.addingTimeInterval(30))
        Task {
            await currentActivity.update(content)
        }
    }

    func endActivity() {
        guard let currentActivity else { return }

        let state = ATPlayerActivityAttributes.ContentState(
            trackTitle: "",
            artistName: "",
            duration: 0,
            currentTime: 0,
            isPlaying: false,
            playbackStartDate: Date.now
        )

        let content = ActivityContent(state: state, staleDate: nil)
        Task {
            await currentActivity.end(content, dismissalPolicy: .immediate)
        }

        self.currentActivity = nil
    }
}
