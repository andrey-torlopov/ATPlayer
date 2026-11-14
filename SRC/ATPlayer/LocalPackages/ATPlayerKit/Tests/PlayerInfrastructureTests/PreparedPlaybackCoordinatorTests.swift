import Foundation
import PlaybackDomain
import XCTest
@testable import PlayerInfrastructure

final class PreparedPlaybackCoordinatorTests: XCTestCase {
    func testAutomaticReplacementStartsAtExactEOF() {
        var coordinator = PreparedPlaybackCoordinator()
        let handle = AudioPreparedTrack(requestID: UUID())
        let plan = coordinator.makePlan(handle: handle, playbackID: UUID(),
                                        earliestStart: 1_256, sampleRate: 48_000, outgoingEnd: 480_000)
        XCTAssertEqual(plan.startFrame, 480_000)
        XCTAssertEqual(plan.handle, handle)
        XCTAssertEqual(coordinator.cancel(), plan)
        XCTAssertNil(coordinator.plan)
    }

    func testShortSourceKeepsItsExactFileBoundary() {
        var coordinator = PreparedPlaybackCoordinator()
        let plan = coordinator.makePlan(handle: AudioPreparedTrack(requestID: UUID()), playbackID: UUID(),
                                        earliestStart: 100, sampleRate: 48_000, outgoingEnd: 1_000)
        XCTAssertEqual(plan.startFrame, 1_000)
    }

    func testManualReplacementUsesEarliestSafeFrameWithoutArtificialInterval() {
        var coordinator = PreparedPlaybackCoordinator()
        let plan = coordinator.makePlan(handle: AudioPreparedTrack(requestID: UUID()), playbackID: UUID(),
                                        earliestStart: 470_256, sampleRate: 48_000, outgoingEnd: nil)
        XCTAssertEqual(plan.startFrame, 470_256)
    }

    func testLateFileStartsAsSoonAsSchedulingAllows() {
        var coordinator = PreparedPlaybackCoordinator()
        let plan = coordinator.makePlan(handle: AudioPreparedTrack(requestID: UUID()), playbackID: UUID(),
                                        earliestStart: 500_256, sampleRate: 48_000, outgoingEnd: 480_000)
        XCTAssertEqual(plan.startFrame, 500_256)
    }

    func testNewPlanInvalidatesPreviousGenerationAndKeepsPlaybackIdentity() {
        var coordinator = PreparedPlaybackCoordinator()
        let first = coordinator.makePlan(handle: AudioPreparedTrack(requestID: UUID()), playbackID: UUID(),
                                         earliestStart: 256, sampleRate: 48_000, outgoingEnd: nil)
        let playbackID = UUID()
        let second = coordinator.makePlan(handle: AudioPreparedTrack(requestID: UUID()), playbackID: playbackID,
                                          earliestStart: 512, sampleRate: 48_000, outgoingEnd: nil)
        XCTAssertGreaterThan(second.generation, first.generation)
        XCTAssertEqual(second.playbackID, playbackID)
        XCTAssertEqual(coordinator.plan, second)
    }
}
