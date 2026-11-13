import Metal
@testable import PlayerFeature
import XCTest

@MainActor
final class AmbientMetalResourceTests: XCTestCase {
    func testRendererLoadsFunctionsAndPipelineFromPackagedLibrary() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("A Metal device is required to validate the packaged shader library.")
        }

        XCTAssertNotNil(
            AmbientGlowRenderer(device: device),
            "The PlayerFeature resource bundle must contain a loadable library and both ambient shader functions."
        )
    }
}
