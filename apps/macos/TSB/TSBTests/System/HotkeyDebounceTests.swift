import AppKit
import XCTest
@testable import TSB

@MainActor
final class HotkeyDebounceTests: XCTestCase {
    func testRepeatedKeyDownWhileHeldEmitsOneToggleIntent() {
        let source = FakeHotkeyEventSource()
        let recorder = IntentRecorder()
        let service = HotkeyService(eventSource: source, onIntent: recorder.record)

        service.start()
        source.sendKeyDown()
        source.sendKeyDown()

        XCTAssertEqual(recorder.intents, [.toggleRecording])
    }

    func testKeyUpAllowsAnotherToggleIntent() {
        let source = FakeHotkeyEventSource()
        let recorder = IntentRecorder()
        let service = HotkeyService(eventSource: source, onIntent: recorder.record)

        service.start()
        source.sendKeyDown()
        source.sendKeyUp()
        source.sendKeyDown()

        XCTAssertEqual(recorder.intents, [.toggleRecording, .toggleRecording])
    }

    func testStopClearsCallbacksSoFutureSourceEventsDoNotEmitIntents() {
        let source = FakeHotkeyEventSource()
        let recorder = IntentRecorder()
        let service = HotkeyService(eventSource: source, onIntent: recorder.record)

        service.start()
        service.stop()
        source.sendKeyDown()

        XCTAssertEqual(recorder.intents, [])
    }

    func testOnlyOptionSpaceMatchesTheLocalShortcut() {
        XCTAssertTrue(LocalHotkeyEventSource.matchesHotkey(keyEvent(modifiers: .option)))
        XCTAssertFalse(LocalHotkeyEventSource.matchesHotkey(keyEvent(modifiers: [.option, .command])))
    }

    private func keyEvent(modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        )!
    }
}

@MainActor
private final class IntentRecorder {
    private(set) var intents: [UserIntent] = []

    func record(_ intent: UserIntent) {
        intents.append(intent)
    }
}

@MainActor
private final class FakeHotkeyEventSource: HotkeyEventSource {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    func start() {}
    func stop() {}

    func sendKeyDown() {
        onKeyDown?()
    }

    func sendKeyUp() {
        onKeyUp?()
    }
}
