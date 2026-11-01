import ActivityKit
import Foundation

nonisolated func requireTransferableActivity<T: ActivityAttributes & Sendable & SendableMetatype>(_: T) {}

@concurrent
func verifyConcurrentPayloadAndActivityKit(
    activity: Activity<ATPlayerActivityAttributes>
) async throws {
    let attributes = ATPlayerActivityAttributes()
    requireTransferableActivity(attributes)
    let state = ATPlayerActivityAttributes.ContentState(
        trackTitle: "Concurrent payload verification",
        artistName: "",
        duration: 120,
        currentTime: 15,
        isPlaying: true,
        playbackStartDate: Date(timeIntervalSince1970: 0)
    )
    let encoded = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(ATPlayerActivityAttributes.ContentState.self, from: encoded)
    _ = Set([state, decoded])
    let content = ActivityContent(state: decoded, staleDate: nil)
    await activity.update(content)
    await activity.end(content, dismissalPolicy: .immediate)
}
