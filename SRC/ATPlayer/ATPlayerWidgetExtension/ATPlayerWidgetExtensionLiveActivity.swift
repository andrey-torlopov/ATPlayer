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
                    Image(systemName: context.state.isPlaying ? "music.note" : "pause.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .accessibilityLabel(context.state.isPlaying ? "Музыка играет" : "На паузе")
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.trackTitle)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .foregroundStyle(.white)

                        if !context.state.artistName.isEmpty {
                            Text(context.state.artistName)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isPlaying {
                        Text(
                            timerInterval: playbackInterval(for: context.state),
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
                        .disabled(!context.state.canPlayPrevious)
                        .opacity(context.state.canPlayPrevious ? 1 : 0.35)
                        .accessibilityLabel("Предыдущий трек")

                        Button(intent: TogglePlaybackIntent()) {
                            Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(context.state.isPlaying ? "Пауза" : "Воспроизвести")

                        Button(intent: NextTrackIntent()) {
                            Image(systemName: "forward.end.fill")
                                .font(.body)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(!context.state.canPlayNext)
                        .opacity(context.state.canPlayNext ? 1 : 0.35)
                        .accessibilityLabel("Следующий трек")
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.isPlaying ? "music.note" : "pause.fill")
                    .foregroundStyle(.cyan)
                    .accessibilityLabel(context.state.isPlaying ? "Музыка играет" : "На паузе")
            } compactTrailing: {
                if context.state.isPlaying {
                    Text(
                        timerInterval: playbackInterval(for: context.state),
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
                Image(systemName: context.state.isPlaying ? "music.note" : "pause.fill")
                    .foregroundStyle(.cyan)
                    .accessibilityLabel(context.state.isPlaying ? "Музыка играет" : "На паузе")
            }
            .widgetURL(URL(string: "atplayer://player"))
        }
    }

    private func lockScreenView(context: ActivityViewContext<ATPlayerActivityAttributes>) -> some View {
        let interval = playbackInterval(for: context.state)

        return VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.trackTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    if !context.state.artistName.isEmpty {
                        Text(context.state.artistName)
                            .font(.subheadline)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            if context.state.isPlaying {
                ProgressView(
                    timerInterval: interval,
                    countsDown: false
                ) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(.cyan)
            } else {
                ProgressView(
                    value: context.state.currentTime,
                    total: max(1, context.state.duration)
                )
                .tint(.cyan)
            }

            HStack {
                if context.state.isPlaying {
                    Text(timerInterval: interval, countsDown: false)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text(formattedTime(context.state.currentTime))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 0) {
                    Text("−")
                    if context.state.isPlaying {
                        Text(timerInterval: interval, countsDown: true)
                    } else {
                        Text(formattedTime(max(0, context.state.duration - context.state.currentTime)))
                    }
                }
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            }

            HStack(spacing: 32) {
                Button(intent: PreviousTrackIntent()) {
                    Image(systemName: "backward.end.fill")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .disabled(!context.state.canPlayPrevious)
                .opacity(context.state.canPlayPrevious ? 1 : 0.35)
                .accessibilityLabel("Предыдущий трек")

                Button(intent: TogglePlaybackIntent()) {
                    Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(context.state.isPlaying ? "Пауза" : "Воспроизвести")

                Button(intent: NextTrackIntent()) {
                    Image(systemName: "forward.end.fill")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .disabled(!context.state.canPlayNext)
                .opacity(context.state.canPlayNext ? 1 : 0.35)
                .accessibilityLabel("Следующий трек")
            }
            .padding(.top, 4)
        }
        .padding(16)
        .activityBackgroundTint(nil)
        .activitySystemActionForegroundColor(nil)
        .widgetURL(URL(string: "atplayer://player"))
    }

    private func playbackInterval(for state: ATPlayerActivityAttributes.ContentState) -> ClosedRange<Date> {
        let duration = state.duration.isFinite ? max(0, state.duration) : 0
        return state.playbackStartDate...state.playbackStartDate.addingTimeInterval(duration)
    }

    private func formattedTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0, seconds < Double(Int.max) else { return "0:00" }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
