import ActivityKit
import Foundation

@MainActor
final class ATPlayerActivityService {
    private var currentActivity: Activity<ATPlayerActivityAttributes>?
    private var lastUpdateTime: Date = .distantPast

    func startActivity(
        trackTitle: String,
        artistName: String,
        duration: TimeInterval
    ) {
        endActivity()

        let state = ATPlayerActivityAttributes.ContentState(
            trackTitle: trackTitle,
            artistName: artistName,
            duration: duration,
            currentTime: 0,
            isPlaying: true
        )

        let content = ActivityContent(
            state: state,
            staleDate: nil
        )

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
        guard now.timeIntervalSince(lastUpdateTime) >= 1.0 else { return }
        lastUpdateTime = now

        let state = ATPlayerActivityAttributes.ContentState(
            trackTitle: trackTitle,
            artistName: artistName,
            duration: duration,
            currentTime: currentTime,
            isPlaying: isPlaying
        )

        let content = ActivityContent(
            state: state,
            staleDate: nil
        )

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
            isPlaying: false
        )

        let content = ActivityContent(
            state: state,
            staleDate: nil
        )

        Task {
            await currentActivity.end(content, dismissalPolicy: .immediate)
        }

        self.currentActivity = nil
    }
}
