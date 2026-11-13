import SwiftUI

struct DeveloperBrandV1: View {
    @Environment(\.playerThemeV1) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 28, height: 24)
            Text("ATPlayer")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .tracking(-0.5)
                .foregroundStyle(theme.textPrimary)
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ATPlayer")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("developer-brand")
    }
}
