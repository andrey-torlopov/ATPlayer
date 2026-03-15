import Combine
import SwiftUI

struct PlayerPanelView: View {
    @ObservedObject var viewModel: ATPlayerViewModel
    @ObservedObject private var playback: AudioPlaybackService
    @Environment(\.theme) private var theme
    let onSettings: () -> Void

    init(viewModel: ATPlayerViewModel, onSettings: @escaping () -> Void) {
        self.viewModel = viewModel
        self.playback = viewModel.playbackService
        self.onSettings = onSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.nowPlayingTitle)
                .font(AppFonts.title(16))
                .foregroundStyle(theme.accent)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(theme.background.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 4) {
                Text(formatted(seconds: playback.currentTime))
                    .font(AppFonts.caption(12))
                    .foregroundStyle(theme.accent)
                    .monospacedDigit()

                Slider(
                    value: Binding(
                        get: { playback.currentTime },
                        set: { viewModel.seek(to: $0) }
                    ),
                    in: 0...max(1, playback.duration)
                )
                .tint(theme.accent)

                Text(formatted(seconds: playback.duration))
                    .font(AppFonts.caption(12))
                    .foregroundStyle(theme.textSecondary)
                    .monospacedDigit()
            }

            TransportControlsView(
                isPlaying: playback.isPlaying,
                onPrevious: viewModel.playPrevious,
                onTogglePlay: viewModel.togglePlayback,
                onNext: viewModel.playNext,
                onSettings: onSettings,
                theme: theme
            )
        }
        .themedPanel()
    }

    private func formatted(seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

struct TransportControlsView: View {
    let isPlaying: Bool
    let onPrevious: () -> Void
    let onTogglePlay: () -> Void
    let onNext: () -> Void
    let onSettings: (() -> Void)?
    let theme: AppTheme

    var body: some View {
        HStack(spacing: 12) {
            ControlButton(symbol: "backward.end.fill", action: onPrevious, theme: theme)
            ControlButton(symbol: isPlaying ? "pause.fill" : "play.fill", action: onTogglePlay, theme: theme)
            ControlButton(symbol: "forward.end.fill", action: onNext, theme: theme)
            Spacer()
            if let onSettings {
                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }
}

private struct ControlButton: View {
    let symbol: String
    let action: () -> Void
    let theme: AppTheme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 44, height: 36)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.accent)
    }
}
