import AppLocalization
import LibraryDomain
import PlaybackDomain
import Combine
import SwiftUI

struct PlayerPanelV1: View {
    @Environment(\.locale) private var locale
    @ObservedObject var viewModel: ATPlayerViewModel
    var isCompact = false
    var isActive = true
    var isInteractive = true
    @Environment(\.playerThemeV1) private var theme

    var body: some View {
        let _ = locale
        VStack(spacing: isCompact ? 12 : 22) {
            Group {
                if isActive {
                    RadialPlayerV1(playback: viewModel.playbackState, onSeek: viewModel.seek)
                } else {
                    // Preserve scroll geometry without subscribing to spectrum frames while hidden.
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
            }
            .frame(maxWidth: isCompact ? 144 : 340)
            .frame(maxWidth: .infinity)

            VStack(spacing: 8) {
                Text(viewModel.selectedTrackID == nil ? L10n.text("Ваш звук. Ничего лишнего.") : viewModel.nowPlayingTitle)
                    .font(.system(isCompact ? .body : .title3, design: .rounded, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(isCompact ? 2 : 3, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)

                if !isCompact {
                    Text(viewModel.selectedTrack?.fileExtensionLabel ?? "")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1.5)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1, reservesSpace: true)
                        .opacity(viewModel.selectedTrackID == nil ? 0 : 1)
                        .accessibilityHidden(viewModel.selectedTrackID == nil)
                }
            }
            .frame(maxWidth: .infinity)

            Group {
                if isActive {
                    TransportControlsV1(viewModel: viewModel, playback: viewModel.playbackState, isCompact: isCompact)
                        .disabled(!isInteractive)
                } else {
                    Color.clear.frame(height: isCompact ? 56 : 78)
                }
            }
            .padding(.top, 2)
        }
        .padding(.bottom, 8)
        .allowsHitTesting(isInteractive)
    }
}

struct TransportControlsV1: View {
    @Environment(\.locale) private var locale
    @ObservedObject var viewModel: ATPlayerViewModel
    let playback: AudioPlaybackState
    var isCompact = false
    @State private var isPlaying = false

    var body: some View {
        let _ = locale
        HStack(spacing: isCompact ? 22 : 30) {
            CircularButtonV1(symbol: "backward.end.fill", label: L10n.text("Предыдущий трек"), size: isCompact ? 44 : 54) {
                viewModel.playPrevious()
            }
            .disabled(!viewModel.canPlayPrevious)

            CircularButtonV1(
                symbol: isPlaying || viewModel.preparingTrackTitle != nil ? "pause.fill" : "play.fill",
                label: isPlaying || viewModel.preparingTrackTitle != nil ? L10n.text("Пауза") : L10n.text("Воспроизвести"),
                size: isCompact ? 56 : 78,
                isProminent: true
            ) {
                viewModel.togglePlayback()
            }
            .disabled(viewModel.selectedTrack == nil && viewModel.preparingTrackTitle == nil)
            .keyboardShortcut(.space, modifiers: [])

            CircularButtonV1(symbol: "forward.end.fill", label: L10n.text("Следующий трек"), size: isCompact ? 44 : 54) {
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

private extension PlaylistTrack {
    var fileExtensionLabel: String {
        URL(fileURLWithPath: filePath).pathExtension.uppercased()
    }
}
