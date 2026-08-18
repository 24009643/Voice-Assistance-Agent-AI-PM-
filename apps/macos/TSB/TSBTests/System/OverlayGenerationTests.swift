import XCTest
@testable import TSB

final class OverlayGenerationTests: XCTestCase {
    func testOlderGenerationDoesNotAcceptDelayedHideCallback() {
        let staleGeneration = OverlayGeneration(1)
        let currentGeneration = OverlayGeneration(2)

        XCTAssertFalse(currentGeneration.accepts(staleGeneration))
    }
}
