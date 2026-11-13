import AppLocalization
import LibraryDomain
import PlaybackDomain
import Combine
import SwiftUI

struct PlayerPanelViewV0: View {
    @Environment(\.locale) private var locale
    @ObservedObject var viewModel: ATPlayerViewModel
    @ObservedObject private var playback: AudioPlaybackState
    @Environment(\.themeV0) private var themeV0
    let onSettings: () -> Void

    init(viewModel: ATPlayerViewModel, onSettings: @escaping () -> Void) {
        self.viewModel = viewModel
        self.playback = viewModel.playbackState
        self.onSettings = onSettings
    }

    var body: some View {
        let _ = locale
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.nowPlayingTitle)
                .font(AppFontsV0.title(16))
                .foregroundStyle(themeV0.accent)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(themeV0.background.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 4) {
                Text(formatted(seconds: playback.currentTime))
                    .font(AppFontsV0.caption(12))
                    .foregroundStyle(themeV0.accent)
                    .monospacedDigit()

                Slider(
                    value: Binding(
                        get: { playback.currentTime },
                        set: { viewModel.seek(to: $0) }
                    ),
                    in: 0...max(1, playback.duration)
                )
                .tint(themeV0.accent)

                Text(formatted(seconds: playback.duration))
                    .font(AppFontsV0.caption(12))
                    .foregroundStyle(themeV0.textSecondary)
                    .monospacedDigit()
            }

            TransportControlsViewV0(
                isPlaying: playback.isPlaying,
                onPrevious: viewModel.playPrevious,
                onTogglePlay: viewModel.togglePlayback,
                onNext: viewModel.playNext,
                onSettings: onSettings,
                themeV0: themeV0
            )
        }
        .themedPanelV0()
    }

    private func formatted(seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

struct TransportControlsViewV0: View {
    let isPlaying: Bool
    let onPrevious: () -> Void
    let onTogglePlay: () -> Void
    let onNext: () -> Void
    let onSettings: (() -> Void)?
    let themeV0: AppThemeV0

    var body: some View {
        HStack(spacing: 12) {
            ControlButtonV0(symbol: "backward.end.fill", action: onPrevious, themeV0: themeV0)
            ControlButtonV0(symbol: isPlaying ? "pause.fill" : "play.fill", action: onTogglePlay, themeV0: themeV0)
            ControlButtonV0(symbol: "forward.end.fill", action: onNext, themeV0: themeV0)
            Spacer()
            if let onSettings {
                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(themeV0.textSecondary)
                }
            }
        }
    }
}

private struct ControlButtonV0: View {
    let symbol: String
    let action: () -> Void
    let themeV0: AppThemeV0

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 44, height: 36)
        }
        .buttonStyle(.borderedProminent)
        .tint(themeV0.accent)
    }
}
