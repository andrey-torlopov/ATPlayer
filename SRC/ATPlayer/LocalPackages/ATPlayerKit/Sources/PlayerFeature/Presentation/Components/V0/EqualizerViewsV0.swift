import AppLocalization
import LibraryDomain
import PlaybackDomain
import SwiftUI
import UIKit

struct NowPlayingVisualizerViewV0: View {
    let artworkData: Data?
    let visualizerValues: [CGFloat]
    @Environment(\.themeV0) private var themeV0

    var body: some View {
        HStack(spacing: 10) {
            if let artworkData, let uiImage = UIImage(data: artworkData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(themeV0.borderLight, lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(themeV0.panel)
                    .frame(width: 70, height: 70)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 24))
                            .foregroundStyle(themeV0.textSecondary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(themeV0.borderLight, lineWidth: 1)
                    )
            }

            VisualizerViewV0(values: visualizerValues)
        }
    }
}

struct VisualizerViewV0: View {
    let values: [CGFloat]
    @Environment(\.themeV0) private var themeV0

    // Keep the original 24-column layout when using the shared 72-band service.
    private var legacyValues: [CGFloat] {
        guard values.count > 24 else { return values }
        return (0..<24).map { values[$0 * values.count / 24] }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(legacyValues.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [themeV0.visualizerLow, themeV0.visualizerHigh],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 6, height: max(6, value * 56))
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 70, maxHeight: 70, alignment: .bottom)
        .background(themeV0.background.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(themeV0.borderLight, lineWidth: 1))
    }
}

struct EqualizerCompactViewV0: View {
    @Environment(\.locale) private var locale
    @ObservedObject var playbackService: AudioPlaybackState
    @Environment(\.themeV0) private var themeV0
    let onTap: () -> Void

    var body: some View {
        let _ = locale
        VStack(alignment: .leading, spacing: 6) {
            VisualizerViewV0(values: playbackService.visualizer)
            HStack(spacing: 8) {
                Text("EQ")
                    .font(AppFontsV0.body(12))
                    .foregroundStyle(themeV0.accent)
                Text(L10n.format("ПРЕДУСИЛЕНИЕ %d дБ", Int(playbackService.preamp)))
                    .font(AppFontsV0.caption())
                    .foregroundStyle(themeV0.textPrimary)
                Spacer()
                Button("EQ") { onTap() }
                    .buttonStyle(.borderedProminent)
                    .tint(themeV0.accentSecondary)
                    .font(AppFontsV0.caption())
            }
        }
        .themedPanelV0()
    }
}

struct EqualizerWindowViewV0: View {
    @Environment(\.locale) private var locale
    @ObservedObject var playbackService: AudioPlaybackState
    @Environment(\.themeV0) private var themeV0

    var body: some View {
        let _ = locale
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Text(L10n.text("ПРЕДУСИЛЕНИЕ"))
                    .foregroundStyle(themeV0.textPrimary)
                    .font(AppFontsV0.caption())
                Text(L10n.format("%d дБ", Int(playbackService.preamp)))
                    .foregroundStyle(themeV0.accent)
                    .font(AppFontsV0.caption())
                Spacer()
                Button(L10n.text("Сбросить")) {
                    playbackService.preamp = 0
                    playbackService.gains = Array(repeating: 0, count: 10)
                }
                .font(AppFontsV0.caption(12))
                .tint(themeV0.destructive)
            }

            Slider(value: Binding(
                get: { Double(playbackService.preamp) },
                set: { playbackService.preamp = Float($0) }
            ), in: -12...12)
            .tint(themeV0.accentSecondary)

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(playbackService.bands.enumerated()), id: \.offset) { index, frequency in
                    VStack(spacing: 4) {
                        Text("\(Int(playbackService.gains[index]))")
                            .foregroundStyle(themeV0.accent)
                            .font(AppFontsV0.caption(9))
                        Slider(value: Binding(
                            get: { Double(playbackService.gains[index]) },
                            set: { playbackService.gains[index] = Float($0) }
                        ), in: -12...12)
                        .rotationEffect(.degrees(-90))
                        .frame(maxHeight: .infinity)
                        Text(label(for: frequency))
                            .foregroundStyle(themeV0.textPrimary)
                            .font(AppFontsV0.caption(10))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)

            VisualizerViewV0(values: playbackService.visualizer)
        }
        .padding()
        .background(themeV0.background.ignoresSafeArea())
        .navigationTitle(L10n.text("Эквалайзер"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func label(for value: Float) -> String {
        if value >= 1000 {
            return "\(Int(value / 1000))k"
        }
        return "\(Int(value))"
    }
}
