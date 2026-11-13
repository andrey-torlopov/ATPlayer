import AppLocalization
import Combine
import PlaybackDomain
import SwiftUI

struct AmbientTransportControlsV1: View {
    @Environment(\.locale) private var locale
    @ObservedObject var viewModel: ATPlayerViewModel
    let playback: AudioPlaybackState
    @State private var isPlayingOrStarting = false

    private var showsPause: Bool {
        isPlayingOrStarting || viewModel.preparingTrackTitle != nil
    }

    var body: some View {
        let _ = locale
        HStack(spacing: 0) {
            AmbientTransportButtonV1(
                symbol: "backward.end.fill", label: L10n.text("Предыдущий трек"), symbolSize: 44,
                restingOpacity: 0.45,
                action: viewModel.playPrevious
            )
            .disabled(!viewModel.canPlayPrevious)
            .accessibilityIdentifier("ambient-previous")

            AmbientTransportButtonV1(
                symbol: showsPause ? "pause.fill" : "play.fill",
                label: showsPause ? L10n.text("Пауза") : L10n.text("Воспроизвести"), symbolSize: 56,
                restingOpacity: 0.5,
                action: viewModel.togglePlayback
            )
            .disabled(viewModel.selectedTrack == nil && viewModel.preparingTrackTitle == nil)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityHint(viewModel.selectedTrack == nil && viewModel.preparingTrackTitle == nil
                ? L10n.text("Выберите трек в вертикальном режиме") : "")
            .accessibilityIdentifier("ambient-toggle")

            AmbientTransportButtonV1(
                symbol: "forward.end.fill", label: L10n.text("Следующий трек"), symbolSize: 44,
                restingOpacity: 0.45,
                action: viewModel.playNext
            )
            .disabled(!viewModel.canPlayNext)
            .accessibilityIdentifier("ambient-next")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        // Audio time and spectrum updates must not invalidate the ambient UI.
        .onReceive(playback.$isPlaying.combineLatest(playback.$isStarting)
            .map { $0 || $1 }.removeDuplicates()) { isPlayingOrStarting = $0 }
    }
}

private struct AmbientTransportButtonV1: View {
    let symbol: String
    let label: String
    let symbolSize: CGFloat
    let restingOpacity: Double
    let action: () -> Void
    @FocusState private var isFocused: Bool
    @AccessibilityFocusState private var isAccessibilityFocused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .regular))
                // The full third of the screen responds to the first tap.
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(AmbientTransportButtonStyleV1(
            symbolSize: symbolSize,
            restingOpacity: restingOpacity,
            hasFocus: isFocused || isAccessibilityFocused
        ))
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .focused($isFocused)
        .accessibilityFocused($isAccessibilityFocused)
        .accessibilityLabel(label)
    }
}

private struct AmbientTransportButtonStyleV1: ButtonStyle {
    let symbolSize: CGFloat
    let restingOpacity: Double
    let hasFocus: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityShowButtonShapes) private var showButtonShapes
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private var needsContrast: Bool {
        contrast == .increased || voiceOverEnabled || reduceTransparency || showButtonShapes
    }

    func makeBody(configuration: Configuration) -> some View {
        let opacity = isEnabled
            ? (needsContrast || hasFocus ? 1 : (configuration.isPressed ? 0.8 : restingOpacity))
            : 0.16

        return configuration.label
            .foregroundStyle(Color.white.opacity(opacity))
            .background {
                Circle()
                    .fill(Color.black.opacity(reduceTransparency ? 1 : (needsContrast || hasFocus ? 0.65 : 0.08)))
                    .overlay {
                        if showButtonShapes || needsContrast || hasFocus {
                            Circle()
                                .strokeBorder(Color.white.opacity(isEnabled ? 0.55 : 0.16), lineWidth: 1)
                        }
                    }
                    .frame(width: symbolSize + 40, height: symbolSize + 40)
                    .allowsHitTesting(false)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: configuration.isPressed)
    }
}
