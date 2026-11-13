import Foundation
@testable import PlayerFeature
import UIKit
import XCTest

@MainActor
final class AvatarResourceTests: XCTestCase {
    func testAvatarResolvesInsidePlayerFeatureResourceBundle() throws {
        let url = try XCTUnwrap(DeveloperAvatarResource.resourceURL,
                               "The PlayerFeature resource bundle must contain avatar.png.")

        XCTAssertEqual(url.lastPathComponent, "avatar.png")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "ATPlayerKit_PlayerFeature.bundle",
                       "The avatar must resolve from its package, not the app asset catalog.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testBundledAvatarCanBeDecodedAndRasterizedByUIKit() throws {
        let url = try XCTUnwrap(DeveloperAvatarResource.resourceURL)
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path),
                                 "UIKit must decode the packaged PNG using its explicit file path.")
        let source = try XCTUnwrap(image.cgImage)
        XCTAssertGreaterThan(source.width, 0)
        XCTAssertGreaterThan(source.height, 0)

        // Drawing forces native pixel decoding instead of checking only file metadata.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let size = CGSize(width: 2, height: 2)
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        let pixels = try XCTUnwrap(rendered.cgImage)
        XCTAssertEqual(pixels.width, 2)
        XCTAssertEqual(pixels.height, 2)
    }

    func testAvatarImageIsCachedAcrossSheetPresentations() throws {
        let first = try XCTUnwrap(DeveloperAvatarResource.image)
        let second = try XCTUnwrap(DeveloperAvatarResource.image)

        XCTAssertTrue(first === second, "Opening the sheet again must not reload its avatar file.")
    }
}
