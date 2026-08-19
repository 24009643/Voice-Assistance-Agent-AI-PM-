import AppKit
import Carbon
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

    func testCarbonEscapePathDeliversOnlyWhileMonitorIsStarted() {
        let source = CarbonHotkeyEventSource(keyCode: UInt32(kVK_Escape), modifiers: 0)
        let monitor = EscapeKeyMonitor(eventSource: source)
        var callbackCount = 0
        monitor.onEscapePressed = { callbackCount += 1 }

        monitor.start()
        source.handle(eventKind: UInt32(kEventHotKeyPressed))
        monitor.stop()
        source.handle(eventKind: UInt32(kEventHotKeyPressed))

        XCTAssertEqual(callbackCount, 1)
    }

    func testEventSourceStartFailureIsReturnedAndDoesNotCallEscapeCallback() {
        let source = FailingEscapeEventSource()
        let monitor = EscapeKeyMonitor(eventSource: source)
        var callbackCount = 0
        monitor.onEscapePressed = { callbackCount += 1 }

        XCTAssertEqual(monitor.start(), .registrationFailed(-1))
        source.sendKeyDown()

        XCTAssertEqual(callbackCount, 0)
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

@MainActor
private final class FailingEscapeEventSource: HotkeyEventSource {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    func start() -> HotkeyStartError? { .registrationFailed(-1) }
    func stop() {}

    func sendKeyDown() {
        onKeyDown?()
    }
}
