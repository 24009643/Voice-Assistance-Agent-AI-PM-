import AVFoundation
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

    func testAuthorizationDecisionUsesAnExplicitSettingsRecoveryPath() {
        XCTAssertEqual(MicrophonePermission.decision(for: .authorized), .proceed)
        XCTAssertEqual(MicrophonePermission.decision(for: .notDetermined), .request)
        XCTAssertEqual(MicrophonePermission.decision(for: .denied), .openSettings)
        XCTAssertEqual(MicrophonePermission.decision(for: .restricted), .openSettings)
    }
}
