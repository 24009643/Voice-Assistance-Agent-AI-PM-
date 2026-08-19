import XCTest
import AppKit
@testable import TSB

final class OverlayGenerationTests: XCTestCase {
    func testDeliveredSnapshotUsesAccessibleGreenConfirmationForOnePointTwoSeconds() throws {
        let presentation = try XCTUnwrap(NotchPresentation.make(for: AppSnapshot(
            status: .delivered,
            elapsedMilliseconds: 0,
            previewText: "Obsidian",
            message: "已复制 · 按 ⌘V 粘贴"
        )))

        XCTAssertEqual(presentation.text, "已复制 · 按 ⌘V 粘贴")
        XCTAssertEqual(presentation.tone, .success)
        XCTAssertEqual(presentation.systemImage, "checkmark.circle.fill")
        XCTAssertEqual(presentation.accessibilityLabel, "复制成功，按 Command V 粘贴")
        XCTAssertEqual(presentation.autoHideDelay, 1.2)
    }

    func testFailureAndDeliveryWarningNeverUseSuccessTone() throws {
        let snapshots = [
            AppSnapshot(status: .failed, elapsedMilliseconds: 0, previewText: "", message: "Could not copy to clipboard."),
            AppSnapshot(status: .delivered, elapsedMilliseconds: 0, previewText: "", message: "已复制，但未能记录复制状态"),
            AppSnapshot(status: .delivered, elapsedMilliseconds: 0, previewText: "已复制 · 按 ⌘V 粘贴", message: nil),
        ]

        for snapshot in snapshots {
            let presentation = try XCTUnwrap(NotchPresentation.make(for: snapshot))
            XCTAssertNotEqual(presentation.tone, .success)
            XCTAssertNil(presentation.autoHideDelay)
        }
    }

    @MainActor
    func testPanelSchedulesDeliveredHideAndRejectsItsCallbackAfterANewerSnapshot() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var scheduled: [(delay: TimeInterval, action: @MainActor () -> Void)] = []
        let panel = NotchOverlayPanel(screen: screen) { delay, action in
            scheduled.append((delay, action))
        }

        panel.update(AppSnapshot(
            status: .delivered,
            elapsedMilliseconds: 0,
            previewText: "Obsidian",
            message: "已复制 · 按 ⌘V 粘贴"
        ))
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(scheduled.map(\.delay), [1.2])

        let staleHide = scheduled[0].action
        panel.update(AppSnapshot(status: .recording, elapsedMilliseconds: 0, previewText: "", message: "Recording"))
        staleHide()
        XCTAssertTrue(panel.isVisible)

        panel.update(AppSnapshot(
            status: .delivered,
            elapsedMilliseconds: 0,
            previewText: "Obsidian",
            message: "已复制 · 按 ⌘V 粘贴"
        ))
        scheduled[1].action()

        XCTAssertFalse(panel.isVisible)
    }

    func testSnapshotRoutingHidesOnlyIdleState() throws {
        XCTAssertNil(NotchPresentation.make(for: AppSnapshot(status: .idle, elapsedMilliseconds: 0, previewText: "", message: nil)))
        XCTAssertEqual(
            try XCTUnwrap(NotchPresentation.make(for: AppSnapshot(status: .recording, elapsedMilliseconds: 0, previewText: "", message: "Recording"))).text,
            "Recording"
        )
    }
}
