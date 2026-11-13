import Foundation
@testable import PlayerFeature
import XCTest

@MainActor
final class PlayerPresentationStateTests: XCTestCase {
    func testDismissingOnePresenterDoesNotUnblockAnother() {
        let state = PlayerPresentationState()
        let editor = UUID()
        let dialog = UUID()

        state.setPresented(true, for: editor)
        state.setPresented(true, for: dialog)
        state.setPresented(false, for: editor)
        XCTAssertTrue(state.hasPresentation, "The remaining dialog must keep ambient rendering paused")
        XCTAssertEqual(state.activePresentations, [dialog])

        state.setPresented(false, for: dialog)
        XCTAssertFalse(state.hasPresentation)
    }

    func testRepeatedAppearanceAndCleanupAreIdempotent() {
        let state = PlayerPresentationState()
        let owner = UUID()
        state.setPresented(true, for: owner)
        state.setPresented(true, for: owner)
        XCTAssertEqual(state.activePresentations.count, 1)

        state.setPresented(false, for: owner)
        state.setPresented(false, for: owner)
        XCTAssertFalse(state.hasPresentation)
    }

    func testLandscapeErrorWaitsForForegroundOrSheetDismissalAndAppearsOnce() {
        var errors = AmbientErrorQueue()
        errors.record("Файл недоступен", isLandscape: true)
        XCTAssertNil(errors.takePending(canPresent: false))
        XCTAssertEqual(errors.takePending(canPresent: true), "Файл недоступен")
        XCTAssertNil(errors.takePending(canPresent: true), "An acknowledged event must not be replayed")
    }

    func testPortraitErrorsAndLeavingLandscapeDoNotProduceStaleAlerts() {
        var errors = AmbientErrorQueue()
        errors.record("Ошибка в библиотеке", isLandscape: false)
        XCTAssertNil(errors.takePending(canPresent: true))
        errors.record("Ошибка трека", isLandscape: true)
        errors.leaveLandscape()
        XCTAssertNil(errors.takePending(canPresent: true))
    }

    func testNewErrorReplacesDeferredMessageAndClearingErrorCancelsIt() {
        var errors = AmbientErrorQueue()
        errors.record("Первая ошибка", isLandscape: true)
        errors.record("Последняя ошибка", isLandscape: true)
        XCTAssertEqual(errors.takePending(canPresent: true), "Последняя ошибка")
        errors.record("Исправленная ошибка", isLandscape: true)
        errors.record(nil, isLandscape: true)
        XCTAssertNil(errors.takePending(canPresent: true))
    }
}
