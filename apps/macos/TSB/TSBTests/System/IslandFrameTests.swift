import AppKit
import XCTest
@testable import TSB

final class IslandFrameTests: XCTestCase {
    func testNotchedBuiltinGeometryAnchorsTheIslandToTheHardwareNotch() {
        let screen = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        let visible = CGRect(x: 0, y: 0, width: 1_512, height: 947)
        let notch = CGRect(x: 632, y: 948, width: 248, height: 34)

        let frame = IslandFrame.make(
            preferredSize: CGSize(width: 520, height: 82),
            screenFrame: screen,
            visibleFrame: visible,
            hardwareNotchFrame: notch
        )

        XCTAssertEqual(frame, CGRect(x: 496, y: 900, width: 520, height: 82))
    }

    func testFallbackUsesMainVisibleFrameAndFixedSafeTopInset() {
        let screen = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let visible = CGRect(x: 0, y: 0, width: 1_920, height: 1_055)

        let frame = IslandFrame.make(
            preferredSize: CGSize(width: 520, height: 82),
            screenFrame: screen,
            visibleFrame: visible,
            hardwareNotchFrame: nil
        )

        XCTAssertEqual(frame, CGRect(x: 700, y: 961, width: 520, height: 82))
    }

    func testFrameClampsWideResultToVisibleScreenMargins() {
        let frame = IslandFrame.make(
            preferredSize: CGSize(width: 890, height: 154),
            screenFrame: CGRect(x: 100, y: 0, width: 700, height: 900),
            visibleFrame: CGRect(x: 100, y: 0, width: 700, height: 875),
            hardwareNotchFrame: nil
        )

        XCTAssertEqual(frame, CGRect(x: 112, y: 709, width: 676, height: 154))
    }

    @MainActor
    func testWindowFrameIsCompactInteractiveAndNonactivating() {
        let requested = CGRect(x: 100, y: 700, width: 520, height: 82)
        let window = NotchWindow(frame: requested)

        XCTAssertEqual(window.frame, requested)
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel))
    }
}
