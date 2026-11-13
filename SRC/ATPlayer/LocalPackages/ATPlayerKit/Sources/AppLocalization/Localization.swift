import Foundation

public enum L10n {
    public static let languageKey = "atplayer.language"

    public static var languageCode: String {
        resolvedLanguageCode(
            selection: UserDefaults.standard.string(forKey: languageKey),
            preferredLanguages: Locale.preferredLanguages
        )
    }

    static func resolvedLanguageCode(selection: String?, preferredLanguages: [String]) -> String {
        if let selection, selection == "ru" || selection == "en" {
            return selection
        }
        return preferredLanguages.first?.hasPrefix("ru") == true ? "ru" : "en"
    }

    public static var locale: Locale { Locale(identifier: languageCode) }

    private static let languageBundles: [String: Bundle] = {
        var bundles: [String: Bundle] = [:]
        for language in ["ru", "en"] {
            if let path = Bundle.module.path(forResource: language, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                bundles[language] = bundle
            }
        }
        return bundles
    }()

    public static func text(_ key: String) -> String {
        text(key, languageCode: languageCode)
    }

    public static func text(_ key: String, languageCode: String) -> String {
        let bundle = languageBundles[languageCode] ?? languageBundles["en"] ?? Bundle.module
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }
}
