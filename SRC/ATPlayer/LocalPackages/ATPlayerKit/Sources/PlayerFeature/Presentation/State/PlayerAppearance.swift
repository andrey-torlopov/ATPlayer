import AppLocalization
import SwiftUI

enum PlayerAppearance: String, CaseIterable {
    case light
    case dark
    case system

    static let storageKey = "atplayer.appearance"

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    var title: String {
        switch self {
        case .light: return L10n.text("Светлая")
        case .dark: return L10n.text("Тёмная")
        case .system: return L10n.text("Системная")
        }
    }

    var symbol: String {
        switch self {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "circle.lefthalf.filled"
        }
    }
}
