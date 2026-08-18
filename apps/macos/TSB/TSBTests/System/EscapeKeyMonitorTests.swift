import AppKit
import XCTest
@testable import TSB

@MainActor
final class EscapeKeyMonitorTests: XCTestCase {
    func testEscapeIsNotConsumedWithoutCallback() {
        let monitor = EscapeKeyMonitor()
        let event = escapeEvent()

        XCTAssertTrue(monitor.handle(event) === event)
    }

    func testEscapeIsConsumedAndCallsCallback() {
        let monitor = EscapeKeyMonitor()
        var callbackCount = 0
        monitor.onEscapePressed = { callbackCount += 1 }

        XCTAssertNil(monitor.handle(escapeEvent()))
        XCTAssertEqual(callbackCount, 1)
    }

    private func escapeEvent() -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        )!
    }
}
