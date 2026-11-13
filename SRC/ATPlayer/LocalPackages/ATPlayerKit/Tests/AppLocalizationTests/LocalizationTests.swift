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
}
