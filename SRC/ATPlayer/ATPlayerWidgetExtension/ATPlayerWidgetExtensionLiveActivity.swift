import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct ATPlayerWidgetExtensionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ATPlayerActivityAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.trackTitle)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .foregroundStyle(.white)

                        Text(context.state.artistName)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isPlaying {
                        Text(
                            timerInterval: context.state.playbackStartDate...context.state.playbackStartDate.addingTimeInterval(context.state.duration),
                            countsDown: false
                        )
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                    } else {
                        Text(formattedTime(context.state.currentTime))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 24) {
                        Button(intent: PreviousTrackIntent()) {
                            Image(systemName: "backward.end.fill")
                                .font(.body)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Button(intent: TogglePlaybackIntent()) {
                            Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Button(intent: NextTrackIntent()) {
                            Image(systemName: "forward.end.fill")
                                .font(.body)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.isPlaying ? "music.note" : "pause.fill")
                    .foregroundStyle(.cyan)
            } compactTrailing: {
                if context.state.isPlaying {
                    Text(
                        timerInterval: context.state.playbackStartDate...context.state.playbackStartDate.addingTimeInterval(context.state.duration),
                        countsDown: false
                    )
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.cyan)
                } else {
                    Text(formattedTime(context.state.currentTime))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.cyan)
                }
            } minimal: {
                Image(systemName: "music.note")
                    .foregroundStyle(.cyan)
            }
        }
    }

    private func lockScreenView(context: ActivityViewContext<ATPlayerActivityAttributes>) -> some View {
        let startDate = context.state.playbackStartDate
        let endDate = startDate.addingTimeInterval(context.state.duration)

        return VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.trackTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Text(context.state.artistName)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if context.state.isPlaying {
                ProgressView(
                    timerInterval: startDate...endDate,
                    countsDown: false
                )
                .tint(.cyan)
            } else {
                ProgressView(
                    value: context.state.currentTime,
                    total: max(1, context.state.duration)
                )
                .tint(.cyan)
            }

            HStack {
                Spacer()

                Text(formattedTime(context.state.duration))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 32) {
                Button(intent: PreviousTrackIntent()) {
                    Image(systemName: "backward.end.fill")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Button(intent: TogglePlaybackIntent()) {
                    Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Button(intent: NextTrackIntent()) {
                    Image(systemName: "forward.end.fill")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .containerBackground(for: .widget) {
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    private func formattedTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
