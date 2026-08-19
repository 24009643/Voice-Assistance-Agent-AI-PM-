import XCTest
@testable import TSB

final class MicrophonePermissionTests: XCTestCase {
    func testRequestLatchAllowsOnlyOneCompletionToStartRecording() {
        var latch = MicrophoneRequestLatch()

        XCTAssertTrue(latch.begin())
        XCTAssertFalse(latch.begin())
        latch.finish()
        XCTAssertTrue(latch.begin())
    }
}
