import UIKit
import XCTest
@testable import PlayerInfrastructure

@MainActor
final class PlaybackBackgroundTaskTests: XCTestCase {
    func testAcquiresSynchronouslyAndEndsOnceAfterCompletion() {
        let identifier = UIBackgroundTaskIdentifier(rawValue: 42)
        var began = false
        var expired: PlaybackBackgroundTask.ExpirationHandler?
        var ended: [UIBackgroundTaskIdentifier] = []
        let task = PlaybackBackgroundTask(
            begin: { expiration in
                began = true
                expired = expiration
                return identifier
            },
            end: { ended.append($0) }
        )

        XCTAssertTrue(began)
        XCTAssertTrue(ended.isEmpty)
        task.finish()
        task.finish()
        expired?()

        XCTAssertEqual(ended, [identifier])
    }

    func testExpirationEndsTaskBeforeAsyncCompletionWithoutRetainingOwner() {
        let identifier = UIBackgroundTaskIdentifier(rawValue: 43)
        var expired: PlaybackBackgroundTask.ExpirationHandler?
        var ended: [UIBackgroundTaskIdentifier] = []
        var task: PlaybackBackgroundTask? = PlaybackBackgroundTask(
            begin: { expiration in
                expired = expiration
                return identifier
            },
            end: { ended.append($0) }
        )
        weak var weakTask = task

        expired?()
        XCTAssertEqual(ended, [identifier])
        task?.finish()
        task = nil

        XCTAssertNil(weakTask)
        expired?()
        XCTAssertEqual(ended, [identifier])
    }

    func testRejectedBackgroundTaskIsNeverEnded() {
        var ended: [UIBackgroundTaskIdentifier] = []
        let task = PlaybackBackgroundTask(begin: { _ in .invalid }, end: { ended.append($0) })

        task.finish()

        XCTAssertTrue(ended.isEmpty)
    }

    func testSynchronousExpirationBalancesIdentifierReturnedAfterward() {
        let identifier = UIBackgroundTaskIdentifier(rawValue: 44)
        var ended: [UIBackgroundTaskIdentifier] = []
        let task = PlaybackBackgroundTask(
            begin: { expiration in
                expiration()
                return identifier
            },
            end: { ended.append($0) }
        )

        XCTAssertEqual(ended, [identifier])
        task.finish()
        XCTAssertEqual(ended, [identifier])
    }
}
