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
    func testCancelledRecordingFeedbackCollapsesToVisibleIdle() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var scheduled: [(TimeInterval, @MainActor () -> Void)] = []
        let panel = NotchOverlayPanel(
            screen: screen,
            onIntent: { _ in },
            schedule: { delay, action in scheduled.append((delay, action)) }
        )

        panel.update(AppSnapshot(
            status: .cancelled,
            elapsedMilliseconds: 0,
            previewText: "",
            message: "Recording cancelled."
        ))

        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled[0].0, 1.2)

        scheduled[0].1()

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.presentedMode, .idle)
    }

    @MainActor
    func testCancelledRecordingFeedbackCollapsesWithActiveSecondaryWork() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var scheduled: [(TimeInterval, @MainActor () -> Void)] = []
        let panel = NotchOverlayPanel(
            screen: screen,
            onIntent: { _ in },
            schedule: { delay, action in scheduled.append((delay, action)) }
        )

        panel.update(AppSnapshot(
            status: .cancelled,
            elapsedMilliseconds: 0,
            previewText: "",
            message: "Recording cancelled.",
            secondaryProcessing: [
                SecondaryProcessingSnapshot(
                    id: SessionID(rawValue: UUID()),
                    status: .delivered,
                    previewText: "older result",
                    message: "整理中",
                    organizationPhase: .organizing
                ),
            ]
        ))

        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled[0].0, 1.2)

        scheduled[0].1()

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

    @MainActor
    func testInitialFallbackIdleIsHiddenWhileHardwareNotchIdleNeverInterceptsClicks() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let idle = AppSnapshot(status: .idle, elapsedMilliseconds: 0, previewText: "", message: nil)
        let fallback = NotchOverlayPanel(
            screen: screen,
            hasHardwareNotch: false,
            onIntent: { _ in }
        )
        let hardwareNotch = NotchOverlayPanel(
            screen: screen,
            hasHardwareNotch: true,
            onIntent: { _ in }
        )

        fallback.update(idle)
        hardwareNotch.update(idle)
        fallback.reattach(to: screen)

        XCTAssertFalse(fallback.isVisible)
        XCTAssertTrue(fallback.isIgnoringMouseEvents)
        XCTAssertTrue(hardwareNotch.isVisible)
        XCTAssertTrue(hardwareNotch.isIgnoringMouseEvents)
    }

    @MainActor
    func testFallbackLatestResultCanCollapseAndReopenWithVisibleButtons() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let sessionID = SessionID(rawValue: UUID())
        let panel = NotchOverlayPanel(
            screen: screen,
            hasHardwareNotch: false,
            onIntent: { _ in }
        )
        panel.update(AppSnapshot(
            sessionID: sessionID,
            status: .delivered,
            elapsedMilliseconds: 0,
            previewText: "cleaned",
            originalText: "raw",
            message: "已复制 · 按 ⌘V 粘贴"
        ))

        panel.perform(.dismiss)
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(panel.isIgnoringMouseEvents)
        XCTAssertEqual(panel.presentedMode, .idle)

        panel.perform(.reopenLatest)
        XCTAssertEqual(panel.presentedMode, .localDelivered)
    }

    @MainActor
    func testScreenParameterNotificationReattachesPanelAndObserverStopsCleanly() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let center = NotificationCenter()
        let panel = NotchOverlayPanel(screen: screen, onIntent: { _ in })
        panel.update(AppSnapshot(
            sessionID: SessionID(rawValue: UUID()),
            status: .recording,
            elapsedMilliseconds: 0,
            previewText: "draft",
            message: "实时草稿"
        ))
        var callbacks = 0
        let observer = ScreenParameterObserver(center: center) {
            callbacks += 1
            panel.reattach(to: screen)
        }

        observer.start()
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        XCTAssertEqual(callbacks, 1)
        let expectedFrame = screen.islandFrame(for: CGSize(width: 520, height: 82))
        let presentedFrame = try XCTUnwrap(panel.presentedFrame)
        XCTAssertEqual(presentedFrame.size, expectedFrame.size)
        XCTAssertEqual(presentedFrame.midX, expectedFrame.midX, accuracy: 1)
        XCTAssertEqual(presentedFrame.maxY, expectedFrame.maxY, accuracy: 1)

        observer.stop()
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(callbacks, 1)
    }

    @MainActor
    func testOrganizedPresentationReflowsOnNarrowReattachAndLatestReopensNarrow() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let sessionID = SessionID(rawValue: UUID())
        let panel = NotchOverlayPanel(screen: screen, onIntent: { _ in })
        panel.reattach(to: screen, visibleWidth: 1_440)
        panel.update(AppSnapshot(
            sessionID: sessionID,
            status: .delivered,
            elapsedMilliseconds: 0,
            previewText: "cleaned organized result",
            originalText: "raw organized result",
            message: "已复制 · 按 ⌘V 粘贴",
            organizationPhase: .organized(organizedRecord())
        ))

        XCTAssertEqual(panel.presentedLayout, .threeChambers)
        panel.reattach(to: screen, visibleWidth: 620)
        XCTAssertEqual(panel.presentedLayout, .singleChamber)
        XCTAssertEqual(panel.presentedSize, CGSize(width: 596, height: 154))

        panel.perform(.dismiss)
        panel.perform(.reopenLatest)

        XCTAssertEqual(panel.presentedLayout, .singleChamber)
        XCTAssertEqual(panel.presentedSize, CGSize(width: 596, height: 154))
        XCTAssertEqual(panel.latestResultSessionID, sessionID)
    }

    @MainActor
    func testScreenObserverDeinitRemovesItsNotificationCallback() {
        let center = NotificationCenter()
        var callbacks = 0
        weak var releasedObserver: ScreenParameterObserver?

        do {
            let observer = ScreenParameterObserver(center: center) { callbacks += 1 }
            releasedObserver = observer
            observer.start()
        }

        XCTAssertNil(releasedObserver)
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(callbacks, 0)
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
