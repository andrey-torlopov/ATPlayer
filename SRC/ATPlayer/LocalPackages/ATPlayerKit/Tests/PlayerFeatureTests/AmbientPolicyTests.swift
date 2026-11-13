import Combine
import CoreGraphics
import Foundation
@testable import PlayerFeature
import XCTest

@MainActor
final class AmbientPolicyTests: XCTestCase {
    func testVisiblePlayingSceneAnimatesAndCanKeepScreenAwake() {
        let policy = makePolicy()

        XCTAssertTrue(policy.isAnimating)
        XCTAssertTrue(policy.shouldKeepAwake)
        XCTAssertEqual(policy.preferredFPS, 30)
        XCTAssertEqual(policy.resolutionScale, 0.5)
    }

    func testHiddenInactiveOrPausedSceneNeverAnimatesOrKeepsScreenAwake() {
        let policies = [
            makePolicy(isVisible: false),
            makePolicy(isSceneActive: false),
            makePolicy(isPlaying: false)
        ]

        for policy in policies {
            XCTAssertFalse(policy.isAnimating, "Inactive presentation must not draw continuously")
            XCTAssertFalse(policy.shouldKeepAwake, "Inactive presentation must release the idle timer")
        }
    }

    func testReducedMotionFreezesDecorationWithoutCancellingKeepAwakePreference() {
        let policy = makePolicy(reduceMotion: true)

        XCTAssertFalse(policy.isAnimating)
        XCTAssertTrue(policy.shouldKeepAwake)
    }

    func testKeepAwakeSettingDoesNotDisableAnimation() {
        let policy = makePolicy(keepsScreenAwake: false)

        XCTAssertTrue(policy.isAnimating)
        XCTAssertFalse(policy.shouldKeepAwake)
    }

    func testLowPowerModeReducesRenderingAndRestoresSystemAutoLock() {
        let policy = makePolicy(isLowPowerModeEnabled: true)

        XCTAssertTrue(policy.isAnimating)
        XCTAssertEqual(policy.preferredFPS, 15)
        XCTAssertEqual(policy.resolutionScale, 0.35)
        XCTAssertFalse(policy.shouldKeepAwake)
    }

    func testThermalPressureProgressivelyReducesAndThenStopsRendering() {
        let fair = makePolicy(thermalState: .fair)
        XCTAssertTrue(fair.isAnimating)
        XCTAssertTrue(fair.shouldKeepAwake)
        XCTAssertEqual(fair.preferredFPS, 15)
        XCTAssertEqual(fair.resolutionScale, 0.35)

        for state in [ProcessInfo.ThermalState.serious, .critical] {
            let policy = makePolicy(thermalState: state)
            XCTAssertFalse(policy.isAnimating)
            XCTAssertFalse(policy.shouldKeepAwake)
        }
    }

    func testScreenModeUsesWindowShapeAndRetainsLastValidMode() {
        XCTAssertEqual(PlayerScreenMode.standard.updated(for: CGSize(width: 844, height: 390)), .ambient)
        XCTAssertEqual(PlayerScreenMode.ambient.updated(for: CGSize(width: 390, height: 844)), .standard)
        XCTAssertEqual(PlayerScreenMode.ambient.updated(for: CGSize(width: 600, height: 600)), .standard)

        let invalidSizes = [
            CGSize.zero,
            CGSize(width: -1, height: 300),
            CGSize(width: 600, height: 0),
            CGSize(width: CGFloat.infinity, height: 300),
            CGSize(width: 600, height: CGFloat.nan)
        ]
        for size in invalidSizes {
            XCTAssertEqual(PlayerScreenMode.ambient.updated(for: size), .ambient)
            XCTAssertEqual(PlayerScreenMode.standard.updated(for: size), .standard)
        }
    }

    func testIdleTimerArbiterOnlyReportsAggregateTransitions() {
        let firstWindow = UUID()
        let secondWindow = UUID()
        var requests = AmbientIdleTimerRequests()

        XCTAssertFalse(requests.isRequested)
        XCTAssertNil(requests.setRequested(false, for: firstWindow))
        XCTAssertEqual(requests.setRequested(true, for: firstWindow), true)
        XCTAssertNil(requests.setRequested(true, for: firstWindow))
        XCTAssertNil(requests.setRequested(true, for: secondWindow))
        XCTAssertNil(requests.setRequested(false, for: firstWindow))
        XCTAssertTrue(requests.isRequested, "The second window still owns its request")
        XCTAssertEqual(requests.setRequested(false, for: secondWindow), false)
        XCTAssertFalse(requests.isRequested)
    }

    func testIdleTimerControllerWritesOnlyWhenTheLastOwnerChanges() {
        let firstWindow = UUID()
        let secondWindow = UUID()
        var writes: [Bool] = []
        let controller = AmbientIdleTimerController { writes.append($0) }

        controller.setRequested(true, for: firstWindow)
        controller.setRequested(true, for: secondWindow)
        controller.setRequested(true, for: firstWindow)
        controller.remove(firstWindow)
        XCTAssertEqual(writes, [true])

        controller.remove(secondWindow)
        controller.remove(secondWindow)
        XCTAssertEqual(writes, [true, false])
    }

    func testIdleTimerControllerReleasesAnOutstandingRequestOnDestruction() {
        var writes: [Bool] = []
        var controller: AmbientIdleTimerController? = AmbientIdleTimerController { writes.append($0) }

        controller?.setRequested(true, for: UUID())
        controller = nil

        XCTAssertEqual(writes, [true, false])
    }

    func testEnvironmentRefreshPublishesOnlyChangedSnapshots() {
        var systemState = AmbientEnvironmentSnapshot(isLowPowerModeEnabled: false, thermalState: .nominal)
        let environment = AmbientEnvironmentState(notificationCenter: NotificationCenter()) { systemState }
        var changes = 0
        let subscription = environment.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }

        environment.refresh()
        XCTAssertEqual(changes, 0)

        systemState = AmbientEnvironmentSnapshot(isLowPowerModeEnabled: true, thermalState: .fair)
        environment.refresh()
        XCTAssertEqual(changes, 1, "A joint system update should produce one observable change")
        XCTAssertTrue(environment.isLowPowerModeEnabled)
        XCTAssertEqual(environment.thermalState, .fair)

        environment.refresh()
        XCTAssertEqual(changes, 1)
    }

    func testEnvironmentSubscriptionsDoNotRetainTheirOwner() {
        let center = NotificationCenter()
        weak var releasedEnvironment: AmbientEnvironmentState?
        autoreleasepool {
            let environment = AmbientEnvironmentState(notificationCenter: center) {
                AmbientEnvironmentSnapshot(isLowPowerModeEnabled: false, thermalState: .nominal)
            }
            releasedEnvironment = environment
            XCTAssertNotNil(releasedEnvironment)
        }

        XCTAssertNil(releasedEnvironment)
    }

    private func makePolicy(
        isVisible: Bool = true,
        isSceneActive: Bool = true,
        isPlaying: Bool = true,
        reduceMotion: Bool = false,
        isLowPowerModeEnabled: Bool = false,
        thermalState: ProcessInfo.ThermalState = .nominal,
        keepsScreenAwake: Bool = true
    ) -> AmbientRenderPolicy {
        AmbientRenderPolicy(
            isVisible: isVisible,
            isSceneActive: isSceneActive,
            isPlaying: isPlaying,
            reduceMotion: reduceMotion,
            isLowPowerModeEnabled: isLowPowerModeEnabled,
            thermalState: thermalState,
            keepsScreenAwake: keepsScreenAwake
        )
    }
}
