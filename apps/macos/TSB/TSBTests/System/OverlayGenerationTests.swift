import AppKit
import XCTest
@testable import TSB

final class OverlayGenerationTests: XCTestCase {
    func testAHideGenerationIsRejectedAfterThePresentationAdvances() {
        let delivered = OverlayGeneration(4)
        let recording = delivered.next()

        XCTAssertFalse(recording.accepts(delivered))
        XCTAssertTrue(recording.accepts(recording))
    }

    @MainActor
    func testScheduledHideCannotDismissANewerRecordingPresentation() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var scheduled: [@MainActor () -> Void] = []
        let panel = NotchOverlayPanel(
            screen: screen,
            onIntent: { _ in },
            schedule: { _, action in scheduled.append(action) }
        )

        panel.update(AppSnapshot(
            status: .delivered,
            elapsedMilliseconds: 0,
            previewText: "local result",
            message: "已复制 · 按 ⌘V 粘贴"
        ))
        XCTAssertEqual(scheduled.count, 1)

        let staleHide = scheduled[0]
        panel.update(AppSnapshot(
            status: .recording,
            elapsedMilliseconds: 0,
            previewText: "new recording",
            message: "实时草稿"
        ))
        staleHide()

        XCTAssertTrue(panel.isVisible)
    }

    @MainActor
    func testSuccessfulDeliveryCollapsesToVisibleIdleSoLatestCanBeReopened() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var scheduled: [@MainActor () -> Void] = []
        let panel = NotchOverlayPanel(
            screen: screen,
            onIntent: { _ in },
            schedule: { _, action in scheduled.append(action) }
        )

        panel.update(AppSnapshot(
            status: .delivered,
            elapsedMilliseconds: 0,
            previewText: "local result",
            message: "已复制 · 按 ⌘V 粘贴"
        ))
        XCTAssertEqual(scheduled.count, 1)

        scheduled[0]()

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.presentedMode, .idle)
    }

    @MainActor
    func testCompletedSecondaryResultIsRetainedWithItsOwnSessionID() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let secondaryID = SessionID(rawValue: UUID())
        let panel = NotchOverlayPanel(screen: screen, onIntent: { _ in })

        panel.update(AppSnapshot(
            status: .recording,
            elapsedMilliseconds: 0,
            previewText: "new recording",
            message: "实时草稿",
            secondaryProcessing: [
                SecondaryProcessingSnapshot(
                    id: secondaryID,
                    status: .delivered,
                    previewText: "older result",
                    message: "已复制 · 按 ⌘V 粘贴",
                    organizationPhase: .organized(organizedRecord())
                ),
            ]
        ))

        XCTAssertEqual(panel.latestResultSessionID, secondaryID)
    }

    private func organizedRecord() -> OrganizationRecord {
        OrganizationRecord(
            requestID: UUID(),
            inputTextSHA256: String(repeating: "a", count: 64),
            state: .succeeded,
            provider: "local",
            model: "deterministic",
            providerKind: .local,
            selectedRecordIDs: [],
            output: OrganizationOutput(
                noResultReason: nil,
                numberedPoints: [],
                knownRecordLinks: [],
                speculativeConnections: []
            ),
            errorCode: nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
