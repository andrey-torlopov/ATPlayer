import AppLocalization
import PlaybackDomain
import SwiftUI

/// Shared by both settings designs and both playback orientations.
struct RadioSettingsView: View {
    @Environment(\.locale) private var locale
    @ObservedObject private var viewModel: ATPlayerViewModel
    @ObservedObject private var playbackState: AudioPlaybackState
    private let primary: Color
    private let secondary: Color
    private let accent: Color

    init(viewModel: ATPlayerViewModel, primary: Color, secondary: Color,
         accent: Color) {
        self.viewModel = viewModel
        self.playbackState = viewModel.playbackState
        self.primary = primary
        self.secondary = secondary
        self.accent = accent
    }

    var body: some View {
        let _ = locale
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.text("Радио"))
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("radio-settings-heading")

            intensityControl(
                title: L10n.text("Радио эффект"),
                subtitle: L10n.text("Максимальный уровень помех"),
                level: viewModel.radioSettings.effectIntensity,
                identifier: "radio-effect-intensity",
                setValue: viewModel.setRadioEffectIntensity
            )

            intensityControl(
                title: L10n.text("Фон радио эффекта"),
                subtitle: L10n.text("Постоянный уровень; 0 разрешает тишину"),
                level: viewModel.radioSettings.backgroundIntensity,
                identifier: "radio-background-intensity",
                setValue: viewModel.setRadioBackgroundIntensity
            )

            if playbackState.radioTemporarilyUnavailable {
                Label(L10n.text("Эффект временно недоступен"), systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("radio-temporarily-unavailable")
            }
        }
        .foregroundStyle(primary)
        .tint(accent)
    }

    private func intensityControl(
        title: String, subtitle: String, level: Int, identifier: String,
        setValue: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title).font(.headline).fixedSize()
                    Spacer(minLength: 0)
                    Text(levelDescription(level)).font(.subheadline).fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(levelDescription(level)).font(.subheadline)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)

            Slider(value: Binding(
                get: { Double(level) },
                set: { setValue(Int($0.rounded())) }
            ), in: 0...10, step: 1) {
                Text(title)
            } minimumValueLabel: {
                Text("0").font(.caption).accessibilityHidden(true)
            } maximumValueLabel: {
                Text("10").font(.caption).accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .accessibilityValue(levelDescription(level))
            .accessibilityHint(subtitle)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: setValue(min(10, level + 1))
                case .decrement: setValue(max(0, level - 1))
                @unknown default: break
                }
            }
            .accessibilityIdentifier(identifier)
        }
    }

    private func levelDescription(_ level: Int) -> String {
        let number = L10n.format("%d из 10", level)
        return level == 0 ? number + " · " + L10n.text("Выключено") : number
    }
}
