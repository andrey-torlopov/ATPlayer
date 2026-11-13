import Foundation
@testable import PlayerFeature
import XCTest

@MainActor
final class ExternalDeveloperLinkTests: XCTestCase {
    func testExplicitActionUsesExactURLsAndDoesNotOpenOnCreation() {
        let action = DeveloperLinkAction()
        var opened: [URL] = []
        XCTAssertNil(action.pendingLink)
        XCTAssertNil(action.failedLink)

        action.open(.boosty) { url, completion in
            opened.append(url)
            completion(true)
        }
        action.open(.repository) { url, completion in
            opened.append(url)
            completion(true)
        }

        XCTAssertEqual(opened.map(\.absoluteString), [
            "https://boosty.to/andreytorlopov",
            "https://github.com/andrey-torlopov/ATPlayer"
        ])
        XCTAssertNil(action.failedLink)
    }

    func testPendingActionCannotOpenAnotherURLAndRejectionCanRetry() {
        let action = DeveloperLinkAction()
        var completion: (@MainActor (Bool) -> Void)?
        var opened: [URL] = []
        action.open(.boosty) { url, callback in
            opened.append(url)
            completion = callback
        }
        action.open(.repository) { url, callback in
            opened.append(url)
            callback(true)
        }
        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(action.pendingLink, .boosty)

        completion?(false)
        XCTAssertNil(action.pendingLink)
        XCTAssertEqual(action.failedLink, .boosty)
        action.open(.boosty) { url, callback in
            opened.append(url)
            callback(true)
        }
        XCTAssertEqual(opened.count, 2)
        XCTAssertNil(action.failedLink)
    }

    func testCopyAfterFailureUsesOriginalAddressAndClearsFailure() {
        let action = DeveloperLinkAction()
        var copied: String?
        action.open(.repository) { _, completion in completion(false) }

        action.copy(.repository) { copied = $0 }

        XCTAssertEqual(copied, "https://github.com/andrey-torlopov/ATPlayer")
        XCTAssertNil(action.failedLink)
        XCTAssertNil(action.pendingLink)
    }
}
