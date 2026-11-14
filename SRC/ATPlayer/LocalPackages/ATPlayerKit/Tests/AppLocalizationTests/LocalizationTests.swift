import XCTest
@testable import AppLocalization

final class LocalizationTests: XCTestCase {
    func testManualSelectionOverridesDeviceLanguage() {
        XCTAssertEqual(L10n.resolvedLanguageCode(selection: "ru", preferredLanguages: ["en-US"]), "ru")
        XCTAssertEqual(L10n.resolvedLanguageCode(selection: "en", preferredLanguages: ["ru-RU"]), "en")
    }

    func testInitialLanguageUsesPrimaryDeviceLanguage() {
        XCTAssertEqual(L10n.resolvedLanguageCode(selection: nil, preferredLanguages: ["ru-RU", "en"]), "ru")
        XCTAssertEqual(L10n.resolvedLanguageCode(selection: nil, preferredLanguages: ["en-US", "ru"]), "en")
        XCTAssertEqual(L10n.resolvedLanguageCode(selection: nil, preferredLanguages: ["fr-FR"]), "en")
        XCTAssertEqual(L10n.resolvedLanguageCode(selection: nil, preferredLanguages: []), "en")
    }

    func testInvalidSavedSelectionFallsBackToDeviceLanguage() {
        XCTAssertEqual(L10n.resolvedLanguageCode(selection: "", preferredLanguages: ["ru"]), "ru")
        XCTAssertEqual(L10n.resolvedLanguageCode(selection: "invalid", preferredLanguages: ["en"]), "en")
    }

    func testBundledTranslationsCanSwitchWithoutChangingGlobalDefaults() {
        XCTAssertEqual(L10n.text("Добавить папку", languageCode: "en"), "Add folder")
        XCTAssertEqual(L10n.text("Добавить папку", languageCode: "ru"), "Добавить папку")
        XCTAssertEqual(L10n.text("Добавить папку", languageCode: "en"), "Add folder")
        XCTAssertEqual(L10n.text("Добавить папку", languageCode: "invalid"), "Add folder")
        XCTAssertEqual(L10n.text("missing-key", languageCode: "en"), "missing-key")
    }

    func testRadioControlsAndAvailabilityAreLocalized() {
        let translations = [
            "Радио": "Radio",
            "Радио эффект": "Radio effect",
            "Максимальный уровень помех": "Maximum interference level",
            "Фон радио эффекта": "Radio effect background",
            "Постоянный уровень; 0 разрешает тишину": "Background level; 0 allows silence",
            "%d из 10": "%d of 10",
            "Выключено": "Off",
            "Эффект временно недоступен": "Effect temporarily unavailable"
        ]
        for (key, english) in translations {
            XCTAssertEqual(L10n.text(key, languageCode: "en"), english)
            XCTAssertEqual(L10n.text(key, languageCode: "ru"), key)
        }
    }
}
