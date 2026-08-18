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
}
