import LibraryDomain
import PlaybackDomain
import SwiftUI

struct PlayerThemeV1: Sendable {
    let background: Color
    let surface: Color
    let elevated: Color
    let inset: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let accent: Color
    let accentSoft: Color
    let border: Color
    let shadow: Color
    let highlight: Color
    let destructive: Color

    static let light = PlayerThemeV1(
        background: Color(red: 0.91, green: 0.93, blue: 0.92),
        surface: Color(red: 0.92, green: 0.94, blue: 0.93),
        elevated: Color(red: 0.95, green: 0.96, blue: 0.95),
        inset: Color(red: 0.85, green: 0.88, blue: 0.86),
        textPrimary: Color(red: 0.16, green: 0.20, blue: 0.18),
        textSecondary: Color(red: 0.36, green: 0.42, blue: 0.38),
        textTertiary: Color(red: 0.43, green: 0.49, blue: 0.45),
        accent: Color(red: 0.30, green: 0.43, blue: 0.36),
        accentSoft: Color(red: 0.79, green: 0.85, blue: 0.81),
        border: Color(red: 0.72, green: 0.77, blue: 0.73),
        shadow: Color(red: 0.65, green: 0.70, blue: 0.67).opacity(0.55),
        highlight: Color.white.opacity(0.90),
        destructive: Color(red: 0.66, green: 0.23, blue: 0.22)
    )

    static let dark = PlayerThemeV1(
        background: Color(red: 0.10, green: 0.12, blue: 0.11),
        surface: Color(red: 0.13, green: 0.15, blue: 0.14),
        elevated: Color(red: 0.17, green: 0.20, blue: 0.18),
        inset: Color(red: 0.08, green: 0.10, blue: 0.09),
        textPrimary: Color(red: 0.91, green: 0.94, blue: 0.92),
        textSecondary: Color(red: 0.64, green: 0.71, blue: 0.66),
        textTertiary: Color(red: 0.56, green: 0.64, blue: 0.59),
        accent: Color(red: 0.66, green: 0.80, blue: 0.71),
        accentSoft: Color(red: 0.23, green: 0.32, blue: 0.26),
        border: Color(red: 0.29, green: 0.35, blue: 0.31),
        shadow: Color.black.opacity(0.50),
        highlight: Color.white.opacity(0.06),
        destructive: Color(red: 1.0, green: 0.56, blue: 0.53)
    )
}

private struct PlayerThemeKeyV1: EnvironmentKey {
    static let defaultValue = PlayerThemeV1.light
}

extension EnvironmentValues {
    var playerThemeV1: PlayerThemeV1 {
        get { self[PlayerThemeKeyV1.self] }
        set { self[PlayerThemeKeyV1.self] = newValue }
    }
}

struct SoftPanelV1: ViewModifier {
    @Environment(\.playerThemeV1) private var theme
    @Environment(\.colorSchemeContrast) private var contrast
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(theme.border.opacity(contrast == .increased ? 1 : 0.45), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: theme.shadow, radius: 12, x: 7, y: 8)
            .shadow(color: theme.highlight, radius: 10, x: -6, y: -6)
    }
}

extension View {
    func softPanelV1(cornerRadius: CGFloat = 24) -> some View {
        modifier(SoftPanelV1(cornerRadius: cornerRadius))
    }

    func playerButtonFeedbackV1(trigger: Bool) -> some View {
        sensoryFeedback(.impact(weight: .light, intensity: 0.45), trigger: trigger)
    }
}

struct SoftButtonStyleV1: ButtonStyle {
    @Environment(\.playerThemeV1) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(configuration.isPressed ? theme.inset : theme.elevated, in: Capsule())
            .overlay { Capsule().strokeBorder(theme.border, lineWidth: 1) }
            .shadow(color: theme.shadow, radius: configuration.isPressed ? 1 : 5, x: 3, y: 4)
            .shadow(color: theme.highlight, radius: configuration.isPressed ? 1 : 5, x: -3, y: -3)
            .opacity(isEnabled ? 1 : 0.45)
    }
}

struct CircularButtonV1: View {
    @Environment(\.playerThemeV1) private var theme
    @State private var feedbackTrigger = false
    let symbol: String
    let label: String
    var size: CGFloat = 48
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button {
            feedbackTrigger.toggle()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size * 0.28, weight: .semibold))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(CircularButtonStyleV1(isProminent: isProminent))
        .playerButtonFeedbackV1(trigger: feedbackTrigger)
        .accessibilityLabel(label)
    }
}

private struct CircularButtonStyleV1: ButtonStyle {
    @Environment(\.playerThemeV1) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isProminent ? theme.background : theme.textPrimary)
            .background {
                Circle()
                    .fill(isProminent ? theme.textPrimary : theme.surface)
                    .shadow(color: theme.shadow, radius: configuration.isPressed ? 2 : 7, x: 5, y: 6)
                    .shadow(color: theme.highlight, radius: configuration.isPressed ? 1 : 7, x: -4, y: -4)
            }
            .overlay {
                Circle().inset(by: 4)
                    .strokeBorder(isProminent ? theme.background.opacity(0.45) : theme.textSecondary.opacity(0.6), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.35)
    }
}
