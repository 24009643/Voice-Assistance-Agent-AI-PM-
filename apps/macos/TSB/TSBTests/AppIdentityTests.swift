import XCTest
@testable import TSB

final class AppIdentityTests: XCTestCase {
    func testIdentityDoesNotUseUpstreamNamespace() {
        XCTAssertEqual(AppIdentity.productName, "TSB")
        XCTAssertEqual(AppIdentity.releaseBundleIdentifier, "com.zhuohengchi.tsb")
        XCTAssertEqual(AppIdentity.developmentBundleIdentifier, "com.zhuohengchi.tsb.dev")
        XCTAssertEqual(AppIdentity.keychainService, "com.zhuohengchi.tsb")
    }
}
