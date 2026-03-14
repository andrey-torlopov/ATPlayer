import SwiftUI
import UIKit

struct VisualizerView: View {
    let values: [CGFloat]
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [theme.visualizerLow, theme.visualizerHigh],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 6, height: max(6, value * 56))
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 70, maxHeight: 70, alignment: .bottom)
        .background(theme.background.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.borderLight, lineWidth: 1))
    }
}

struct EqualizerCompactView: View {
    @ObservedObject var playbackService: AudioPlaybackService
    @Environment(\.theme) private var theme
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VisualizerView(values: playbackService.visualizer)
            HStack(spacing: 8) {
                Text("EQ")
                    .font(AppFonts.body(12))
                    .foregroundStyle(theme.accent)
                Text("PREAMP \(Int(playbackService.preamp)) dB")
                    .font(AppFonts.caption())
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button("EQ") { onTap() }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accentSecondary)
                    .font(AppFonts.caption())
            }
        }
        .themedPanel()
    }
}

struct EqualizerWindowView: View {
    @ObservedObject var playbackService: AudioPlaybackService
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("EQUALIZER")
                    .font(AppFonts.title())
                    .foregroundStyle(theme.accent)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("PREAMP")
                    .foregroundStyle(theme.textPrimary)
                    .font(AppFonts.caption())
                Slider(value: Binding(
                    get: { Double(playbackService.preamp) },
                    set: { playbackService.preamp = Float($0) }
                ), in: -12...12)
                .tint(theme.accentSecondary)
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(playbackService.bands.enumerated()), id: \.offset) { index, frequency in
                    VStack {
                        Slider(value: Binding(
                            get: { Double(playbackService.gains[index]) },
                            set: { playbackService.gains[index] = Float($0) }
                        ), in: -12...12)
                        .rotationEffect(.degrees(-90))
                        .frame(height: 110)
                        Text(label(for: frequency))
                            .foregroundStyle(theme.textPrimary)
                            .font(AppFonts.caption(10))
                    }
                }
            }

            VisualizerView(values: playbackService.visualizer)
        }
        .padding()
        .background(theme.background)
        .onAppear {
            setLandscape(true)
        }
        .onDisappear {
            setLandscape(false)
        }
    }

    private func label(for value: Float) -> String {
        if value >= 1000 {
            return "\(Int(value / 1000))k"
        }
        return "\(Int(value))"
    }

    private func setLandscape(_ lock: Bool) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        if lock {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
        } else {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .all))
        }
    }
}
