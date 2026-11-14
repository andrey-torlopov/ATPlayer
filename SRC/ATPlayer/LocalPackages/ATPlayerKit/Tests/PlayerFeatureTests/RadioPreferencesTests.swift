import Foundation
import PlaybackDomain
@testable import PlayerFeature
import XCTest

@MainActor
final class RadioPreferencesTests: XCTestCase {
    func testFirstLaunchIsDry() throws {
        let fixture = try PreferencesFixture()
        defer { fixture.cleanup() }
        XCTAssertEqual(fixture.preferences.load(), RadioSettings())
        XCTAssertTrue(fixture.preferences.load().isBypassed)
    }

    func testSingleLevelSurvivesReopeningAndCanBeDisabled() throws {
        let fixture = try PreferencesFixture()
        defer { fixture.cleanup() }
        let reopened = RadioPreferences(defaults: fixture.defaults)
        for level in [7, 0, 10] {
            fixture.preferences.save(RadioSettings(effectIntensity: level))
            XCTAssertEqual(reopened.load(), RadioSettings(effectIntensity: level))
        }
    }

    func testLegacyStationSearchAndProfileAreIgnoredAndRemovedOnSave() throws {
        let fixture = try PreferencesFixture()
        defer { fixture.cleanup() }
        fixture.defaults.set(10, forKey: RadioPreferences.legacyTransitionIntensityKey)
        fixture.defaults.set("fmAnalog.v1", forKey: RadioPreferences.legacyProfileIDKey)
        XCTAssertTrue(fixture.preferences.load().isBypassed)
        fixture.defaults.set(7, forKey: RadioPreferences.effectIntensityKey)
        let migrated = fixture.preferences.load()
        XCTAssertEqual(migrated, RadioSettings(effectIntensity: 7))
        fixture.preferences.save(migrated)
        XCTAssertNil(fixture.defaults.object(forKey: RadioPreferences.legacyTransitionIntensityKey))
        XCTAssertNil(fixture.defaults.object(forKey: RadioPreferences.legacyProfileIDKey))
    }

    func testOutOfRangeIntegersClamp() throws {
        let fixture = try PreferencesFixture()
        defer { fixture.cleanup() }
        fixture.defaults.set(-100, forKey: RadioPreferences.effectIntensityKey)
        XCTAssertEqual(fixture.preferences.load().effectIntensity, 0)
        fixture.defaults.set(Int.max, forKey: RadioPreferences.effectIntensityKey)
        XCTAssertEqual(fixture.preferences.load().effectIntensity, 10)
    }

    func testUnreadableSavedValuesDoNotCoerceStringsOrBooleans() throws {
        let fixture = try PreferencesFixture()
        defer { fixture.cleanup() }
        let invalidValues: [Any] = ["7", "invalid", true, 5.5, Data([1, 2])]
        for value in invalidValues {
            fixture.defaults.set(value, forKey: RadioPreferences.effectIntensityKey)
            XCTAssertEqual(fixture.preferences.load(), RadioSettings())
        }
        fixture.defaults.removeObject(forKey: RadioPreferences.effectIntensityKey)
        XCTAssertEqual(fixture.preferences.load(), RadioSettings())
    }

    func testDecodeIgnoresRemovedOptionsAndEncodesBothNoiseLevels() throws {
        let legacy = Data(#"{"effectIntensity":99,"transitionIntensity":10,"profileID":"future-radio"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(RadioSettings.self, from: legacy), RadioSettings(effectIntensity: 10))
        let invalid = Data(#"{"effectIntensity":"invalid","transitionIntensity":10}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(RadioSettings.self, from: invalid).isBypassed)
        let settings = RadioSettings(effectIntensity: 3)
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(RadioSettings.self, from: data), settings)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Int])
        XCTAssertEqual(payload, ["effectIntensity": 3, "backgroundIntensity": 3])
    }

    func testBackgroundRaisesMaximumAndBothLevelsClamp() throws {
        XCTAssertEqual(RadioSettings(effectIntensity: 4, backgroundIntensity: 7),
                       RadioSettings(effectIntensity: 7, backgroundIntensity: 7))
        XCTAssertEqual(RadioSettings(effectIntensity: 99, backgroundIntensity: -1),
                       RadioSettings(effectIntensity: 10, backgroundIntensity: 0))
        XCTAssertEqual(RadioSettings(effectIntensity: -1, backgroundIntensity: 99),
                       RadioSettings(effectIntensity: 10, backgroundIntensity: 10))
        let data = Data(#"{"effectIntensity":3,"backgroundIntensity":7}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(RadioSettings.self, from: data),
                       RadioSettings(effectIntensity: 7, backgroundIntensity: 7))
    }

    func testSeparateBackgroundSurvivesReopeningIncludingExplicitZero() throws {
        let fixture = try PreferencesFixture()
        defer { fixture.cleanup() }
        let reopened = RadioPreferences(defaults: fixture.defaults)
        for background in [0, 4, 7] {
            let settings = RadioSettings(effectIntensity: 7, backgroundIntensity: background)
            fixture.preferences.save(settings)
            XCTAssertEqual(reopened.load(), settings)
        }
    }

    func testEffectHasAnExactFunctionalZero() {
        XCTAssertTrue(RadioSettings().isBypassed)
        XCTAssertFalse(RadioSettings().isEffectActive)
        XCTAssertTrue(RadioSettings(effectIntensity: 1).isEffectActive)
        XCTAssertFalse(RadioSettings(effectIntensity: 10).isBypassed)
    }
}

@MainActor
private struct PreferencesFixture {
    let suiteName: String
    let defaults: UserDefaults
    let preferences: RadioPreferences

    init() throws {
        suiteName = "ATPlayer.RadioPreferencesTests." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        preferences = RadioPreferences(defaults: defaults)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
