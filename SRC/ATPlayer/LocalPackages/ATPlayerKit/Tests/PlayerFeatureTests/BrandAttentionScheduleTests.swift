import Foundation
@testable import PlayerFeature
import XCTest

final class BrandAttentionScheduleTests: XCTestCase {
    func testFirstEventRequiresFullEligibleInterval() {
        let start = ContinuousClock.now
        var schedule = BrandAttentionSchedule()
        schedule.setEligible(true, at: start)

        XCTAssertFalse(schedule.fireIfDue(at: start.advanced(by: .seconds(299))))
        XCTAssertTrue(schedule.fireIfDue(at: start.advanced(by: .seconds(300))))
        XCTAssertFalse(schedule.fireIfDue(at: start.advanced(by: .seconds(300))))
        XCTAssertEqual(schedule.delay(at: start.advanced(by: .seconds(300))), .seconds(300))
    }

    func testHiddenTimeDoesNotConsumeRemainingInterval() {
        let start = ContinuousClock.now
        var schedule = BrandAttentionSchedule()
        schedule.setEligible(true, at: start)
        schedule.setEligible(false, at: start.advanced(by: .seconds(120)))

        let returned = start.advanced(by: .seconds(10_000))
        XCTAssertFalse(schedule.fireIfDue(at: returned))
        XCTAssertEqual(schedule.delay(at: returned), .seconds(180))
        schedule.setEligible(true, at: returned)
        XCTAssertFalse(schedule.fireIfDue(at: returned.advanced(by: .seconds(179))))
        XCTAssertTrue(schedule.fireIfDue(at: returned.advanced(by: .seconds(180))))
    }

    func testRepeatedEligibilityDoesNotRestartOrDoubleCount() {
        let start = ContinuousClock.now
        var schedule = BrandAttentionSchedule()
        schedule.setEligible(true, at: start)
        schedule.setEligible(true, at: start.advanced(by: .seconds(100)))
        schedule.setEligible(false, at: start.advanced(by: .seconds(200)))
        schedule.setEligible(false, at: start.advanced(by: .seconds(250)))

        XCTAssertEqual(schedule.delay(at: start.advanced(by: .seconds(900))), .seconds(100))
    }

    func testLateWakeEmitsOnlyOneEventWithoutCatchUp() {
        let start = ContinuousClock.now
        var schedule = BrandAttentionSchedule()
        schedule.setEligible(true, at: start)
        let lateWake = start.advanced(by: .seconds(1_500))

        XCTAssertTrue(schedule.fireIfDue(at: lateWake))
        XCTAssertFalse(schedule.fireIfDue(at: lateWake))
        XCTAssertEqual(schedule.delay(at: lateWake), .seconds(300))
    }

    func testTapResetsVisibleAndSuspendedSchedules() {
        let start = ContinuousClock.now
        var schedule = BrandAttentionSchedule()
        schedule.setEligible(true, at: start)
        let tap = start.advanced(by: .seconds(299))
        schedule.reset(at: tap)

        XCTAssertFalse(schedule.fireIfDue(at: tap))
        XCTAssertEqual(schedule.delay(at: tap), .seconds(300))
        schedule.setEligible(false, at: tap.advanced(by: .seconds(50)))
        schedule.reset(at: tap.advanced(by: .seconds(100)))
        XCTAssertEqual(schedule.delay(at: tap.advanced(by: .seconds(200))), .seconds(300))
    }

    func testDisablingAtDeadlineDoesNotFireWhileIneligible() {
        let start = ContinuousClock.now
        var schedule = BrandAttentionSchedule()
        schedule.setEligible(true, at: start)
        let deadline = start.advanced(by: .seconds(300))
        schedule.setEligible(false, at: deadline)

        XCTAssertFalse(schedule.fireIfDue(at: deadline))
        XCTAssertFalse(schedule.fireIfDue(at: deadline.advanced(by: .seconds(300))))
    }
}
