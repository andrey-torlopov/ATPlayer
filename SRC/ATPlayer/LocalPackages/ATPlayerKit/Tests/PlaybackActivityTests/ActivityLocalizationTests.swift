import Foundation
import PlaybackActivity
import XCTest

final class ActivityLocalizationTests: XCTestCase {
    func testDecodingActivityCreatedBeforeLanguageWasAdded() throws {
        let legacyJSON = Data("""
        {
          "trackID": "2D13C1EB-3F4D-42EE-BCC2-C5A1BF6DD83B",
          "trackTitle": "Existing track",
          "artistName": "Existing artist",
          "duration": 180,
          "currentTime": 45,
          "isPlaying": true,
          "playbackStartDate": 0,
          "canPlayPrevious": false,
          "canPlayNext": true
        }
        """.utf8)

        let state = try JSONDecoder().decode(ATPlayerActivityAttributes.ContentState.self, from: legacyJSON)

        XCTAssertNil(state.languageCode, "Activities from earlier app versions must remain decodable.")
        XCTAssertEqual(state.trackTitle, "Existing track")
        XCTAssertEqual(state.currentTime, 45)
        XCTAssertTrue(state.isPlaying)
        XCTAssertFalse(state.canPlayPrevious)
        XCTAssertTrue(state.canPlayNext)
    }

    func testSelectedLanguageSurvivesActivityStateEncoding() throws {
        let trackID = UUID()
        for language in ["ru", "en"] {
            let state = ATPlayerActivityAttributes.ContentState(
                trackID: trackID, trackTitle: "Track", artistName: "Artist",
                duration: 180, currentTime: 45, isPlaying: false,
                playbackStartDate: Date(timeIntervalSinceReferenceDate: 0),
                canPlayPrevious: true, canPlayNext: true, languageCode: language
            )

            let data = try JSONEncoder().encode(state)
            let restored = try JSONDecoder().decode(ATPlayerActivityAttributes.ContentState.self, from: data)

            XCTAssertEqual(restored.languageCode, language,
                           "The extension must receive the app's choice instead of using its own defaults.")
            XCTAssertEqual(restored, state)
        }
    }
}
