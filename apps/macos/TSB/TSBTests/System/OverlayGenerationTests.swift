import XCTest
@testable import TSB

final class OverlayGenerationTests: XCTestCase {
    func testOlderGenerationDoesNotAcceptDelayedHideCallback() {
        let staleGeneration = OverlayGeneration(1)
        let currentGeneration = OverlayGeneration(2)

        XCTAssertFalse(currentGeneration.accepts(staleGeneration))
    }

    func testSnapshotRoutingHidesOnlyIdleState() {
        XCTAssertNil(NotchPresentation.text(for: AppSnapshot(status: .idle, elapsedMilliseconds: 0, previewText: "", message: nil)))
        XCTAssertEqual(
            NotchPresentation.text(for: AppSnapshot(status: .recording, elapsedMilliseconds: 0, previewText: "", message: "Recording")),
            "Recording"
        )
        XCTAssertEqual(
            NotchPresentation.text(for: AppSnapshot(status: .delivered, elapsedMilliseconds: 0, previewText: "", message: "Copied to clipboard.")),
            "Copied to clipboard."
        )
    }
}
