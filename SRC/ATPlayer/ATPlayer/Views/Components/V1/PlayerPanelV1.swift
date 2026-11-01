import Combine
import SwiftUI

struct PlayerPanelV1: View {
    @ObservedObject var viewModel: ATPlayerViewModel
    var isCompact = false
    @Environment(\.playerThemeV1) private var theme

    var body: some View {
        VStack(spacing: isCompact ? 12 : 22) {
            RadialPlayerV1(playback: viewModel.playbackService, onSeek: viewModel.seek)
                .frame(maxWidth: isCompact ? 144 : 340)
                .frame(maxWidth: .infinity)

            VStack(spacing: 8) {
                Text(viewModel.selectedTrackID == nil ? "Ваш звук. Ничего лишнего." : viewModel.nowPlayingTitle)
                    .font(.system(isCompact ? .body : .title3, design: .rounded, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(isCompact ? 2 : 3)
                    .fixedSize(horizontal: false, vertical: true)

                if !isCompact, let track = viewModel.selectedTrack, viewModel.selectedTrackID != nil {
                    Text(track.fileExtensionLabel)
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1.5)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)

            TransportControlsV1(viewModel: viewModel, playback: viewModel.playbackService, isCompact: isCompact)
                .padding(.top, 2)
        }
        .padding(.bottom, 8)
    }
}

struct TransportControlsV1: View {
    @ObservedObject var viewModel: ATPlayerViewModel
    let playback: AudioPlaybackService
    var isCompact = false
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: isCompact ? 22 : 30) {
            CircularButtonV1(symbol: "backward.end.fill", label: "Предыдущий трек", size: isCompact ? 44 : 54) {
                viewModel.playPrevious()
            }
            .disabled(!viewModel.canPlayPrevious)

            CircularButtonV1(
                symbol: isPlaying ? "pause.fill" : "play.fill",
                label: isPlaying ? "Пауза" : "Воспроизвести",
                size: isCompact ? 56 : 78,
                isProminent: true
            ) {
                viewModel.togglePlayback()
            }
            .disabled(viewModel.selectedTrack == nil)
            .keyboardShortcut(.space, modifiers: [])

            CircularButtonV1(symbol: "forward.end.fill", label: "Следующий трек", size: isCompact ? 44 : 54) {
                viewModel.playNext()
            }
            .disabled(!viewModel.canPlayNext)
        }
        .frame(maxWidth: .infinity)
        // Spectrum frames should redraw the dial, not sort the library for transport state.
        .onReceive(playback.$isPlaying.combineLatest(playback.$isStarting)
            .map { $0 || $1 }.removeDuplicates()) { isPlaying = $0 }
    }
}

private extension TrackItem {
    var fileExtensionLabel: String {
        URL(fileURLWithPath: filePath).pathExtension.uppercased()
    }
}
