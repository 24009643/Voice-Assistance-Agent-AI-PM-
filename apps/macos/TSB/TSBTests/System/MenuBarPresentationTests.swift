import XCTest
@testable import TSB

final class MenuBarPresentationTests: XCTestCase {
    func testUnavailableRecordingMenuShowsFallbackWithoutWritingPreviewText() {
        let snapshot = AppSnapshot(
            status: .recording,
            elapsedMilliseconds: 0,
            previewText: "",
            message: "Recording",
            livePreviewAvailability: .unavailable
        )

        let presentation = MenuBarPresentation.make(for: snapshot)

        XCTAssertEqual(snapshot.previewText, "")
        XCTAssertEqual(presentation.recordingStatusText, "实时草稿不可用，停止后仍会生成全文")
    }
}
