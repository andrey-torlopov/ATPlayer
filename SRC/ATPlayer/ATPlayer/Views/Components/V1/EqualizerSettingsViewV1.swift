import SwiftUI

struct EqualizerSettingsViewV1: View {
    @ObservedObject var playbackService: AudioPlaybackService
    @Environment(\.playerThemeV1) private var theme
    @State private var resetFeedbackTrigger = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("Предусиление")
                    EqualizerGainControlV1(
                        title: "Общий уровень",
                        accessibilityTitle: "Предусиление",
                        value: Binding(
                            get: { Double(playbackService.preamp) },
                            set: { playbackService.preamp = Float($0) }
                        )
                    )
                    .padding(20)
                    .softPanelV1()
                }

                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        sectionLabel("Частоты")
                        Spacer()
                        Text("−12 … +12 дБ")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.textTertiary)
                    }

                    VStack(spacing: 22) {
                        ForEach(Array(playbackService.bands.enumerated()), id: \.offset) { index, frequency in
                            EqualizerGainControlV1(
                                title: frequencyLabel(frequency),
                                accessibilityTitle: "Частота \(frequencyLabel(frequency))",
                                value: gainBinding(at: index)
                            )
                        }
                    }
                    .padding(20)
                    .softPanelV1()
                }

                Button {
                    resetFeedbackTrigger.toggle()
                    playbackService.preamp = 0
                    playbackService.gains = Array(repeating: 0, count: playbackService.bands.count)
                } label: {
                    Label("Сбросить настройки", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 20)
                }
                .buttonStyle(SoftButtonStyleV1())
                .playerButtonFeedbackV1(trigger: resetFeedbackTrigger)

                Text("Настройки применяются сразу и сохраняются автоматически.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Эквалайзер")
        .navigationBarTitleDisplayMode(.inline)
        .tint(theme.accent)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .tracking(2)
            .foregroundStyle(theme.textSecondary)
    }

    private func frequencyLabel(_ frequency: Float) -> String {
        if frequency >= 1_000 {
            return String(format: "%g кГц", frequency / 1_000)
        }
        return "\(Int(frequency)) Гц"
    }

    private func gainBinding(at index: Int) -> Binding<Double> {
        Binding(
            get: {
                guard playbackService.gains.indices.contains(index) else { return 0 }
                return Double(playbackService.gains[index])
            },
            set: { value in
                guard playbackService.gains.indices.contains(index) else { return }
                playbackService.gains[index] = Float(value)
            }
        )
    }
}

private struct EqualizerGainControlV1: View {
    let title: String
    let accessibilityTitle: String
    @Binding var value: Double
    @Environment(\.playerThemeV1) private var theme

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text("\(value, specifier: "%+.1f") дБ")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.accent)
            }
            Slider(value: $value, in: -12...12, step: 0.5)
                .tint(theme.accent)
                .accessibilityLabel(accessibilityTitle)
                .accessibilityValue(Text("\(value, specifier: "%.1f") децибел"))
        }
    }
}
