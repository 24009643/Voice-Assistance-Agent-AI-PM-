import XCTest
@testable import TSB

@MainActor
final class AppIdentityTests: XCTestCase {
    func testIdentityDoesNotUseUpstreamNamespace() {
        XCTAssertEqual(AppIdentity.productName, "TSB")
        XCTAssertEqual(AppIdentity.releaseBundleIdentifier, "com.zhuohengchi.tsb")
        XCTAssertEqual(AppIdentity.developmentBundleIdentifier, "com.zhuohengchi.tsb.dev")
        XCTAssertEqual(AppIdentity.keychainService, "com.zhuohengchi.tsb")
    }

    func testQueuedOlderCompletionCannotStopEscapeBetweenPreflightAndRecordingStart() async {
        var monitorIsActive = false
        var mainIsRecording = false
        var didStartRecording = false
        let olderCompletionRan = expectation(description: "older completion ran")

        let error = AppController.startRecordingAfterEscapePreflight(
            startEscape: {
                monitorIsActive = true
                Task { @MainActor in
                    if !mainIsRecording {
                        monitorIsActive = false
                    }
                    olderCompletionRan.fulfill()
                }
                return nil
            },
            startRecording: {
                XCTAssertTrue(monitorIsActive)
                mainIsRecording = true
                didStartRecording = true
            }
        )

        XCTAssertNil(error)
        XCTAssertTrue(didStartRecording)
        await fulfillment(of: [olderCompletionRan], timeout: 1)
        XCTAssertTrue(monitorIsActive)
    }

    func testEscapeRegistrationFailureDoesNotStartRecording() {
        var didStartRecording = false

        let error = AppController.startRecordingAfterEscapePreflight(
            startEscape: { .registrationFailed(-7) },
            startRecording: { didStartRecording = true }
        )

        XCTAssertEqual(error, .registrationFailed(-7))
        XCTAssertFalse(didStartRecording)
    }
}
