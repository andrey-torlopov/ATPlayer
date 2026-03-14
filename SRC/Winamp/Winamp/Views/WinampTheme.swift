import SwiftUI

struct AppTheme: Sendable {
    let background: Color
    let panel: Color
    let borderLight: Color
    let borderDark: Color
    let accent: Color
    let accentSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let destructive: Color
    let visualizerLow: Color
    let visualizerHigh: Color

    static let dark = AppTheme(
        background: Color(red: 0.08, green: 0.08, blue: 0.10),
        panel: Color(red: 0.13, green: 0.13, blue: 0.16),
        borderLight: Color(red: 0.25, green: 0.25, blue: 0.30),
        borderDark: Color(red: 0.04, green: 0.04, blue: 0.06),
        accent: Color(red: 0.35, green: 0.60, blue: 1.0),
        accentSecondary: Color(red: 0.95, green: 0.55, blue: 0.20),
        textPrimary: Color.white,
        textSecondary: Color.white.opacity(0.6),
        destructive: Color.red,
        visualizerLow: Color(red: 0.35, green: 0.60, blue: 1.0),
        visualizerHigh: Color(red: 0.95, green: 0.55, blue: 0.20)
    )

    static let light = AppTheme(
        background: Color(red: 0.95, green: 0.95, blue: 0.96),
        panel: Color.white,
        borderLight: Color(red: 0.85, green: 0.85, blue: 0.87),
        borderDark: Color(red: 0.78, green: 0.78, blue: 0.80),
        accent: Color(red: 0.20, green: 0.45, blue: 0.90),
        accentSecondary: Color(red: 0.90, green: 0.50, blue: 0.15),
        textPrimary: Color(red: 0.10, green: 0.10, blue: 0.12),
        textSecondary: Color(red: 0.40, green: 0.40, blue: 0.45),
        destructive: Color.red,
        visualizerLow: Color(red: 0.20, green: 0.45, blue: 0.90),
        visualizerHigh: Color(red: 0.90, green: 0.50, blue: 0.15)
    )
}

struct AppFonts {
    static func title(_ size: CGFloat = 18) -> Font {
        .system(size: size, weight: .heavy, design: .monospaced)
    }

    static func body(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }

    static func caption(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.dark
}

extension EnvironmentValues {
    var theme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

struct ThemedPanel: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.borderLight, lineWidth: 1)
            )
    }
}

extension View {
    func themedPanel() -> some View {
        modifier(ThemedPanel())
    }
}
