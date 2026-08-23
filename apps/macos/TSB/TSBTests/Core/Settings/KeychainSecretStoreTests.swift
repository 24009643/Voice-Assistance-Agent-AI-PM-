import Foundation
import XCTest
@testable import TSB

final class KeychainSecretStoreTests: XCTestCase {
    func testSaveLoadAndDeleteRoundTrip() throws {
        let store = makeStore()
        defer { try? store.delete() }
        let dummySecret = UUID().uuidString

        try store.save(dummySecret)
        XCTAssertEqual(try store.load(), dummySecret)

        try store.delete()
        XCTAssertNil(try store.load())
    }

    func testDeletingMissingSecretSucceeds() throws {
        let store = makeStore()
        defer { try? store.delete() }

        try store.delete()

        XCTAssertNil(try store.load())
    }

    func testFailedReplacementPreservesExistingSecret() throws {
        let service = "KeychainSecretStoreTests.\(UUID().uuidString)"
        let account = "api-key"
        let stableStore = KeychainSecretStore(service: service, account: account)
        defer { try? stableStore.delete() }
        let originalSecret = UUID().uuidString

        try stableStore.save(originalSecret)
        let failingStore = KeychainSecretStore(
            service: service,
            account: account,
            update: { _, _ in errSecAuthFailed },
            add: { _ in
                XCTFail("Replacement must not add when the item exists")
                return errSecSuccess
            }
        )

        XCTAssertThrowsError(try failingStore.save(UUID().uuidString)) { error in
            XCTAssertEqual(error as? KeychainSecretStoreError, .unexpectedStatus(errSecAuthFailed))
        }
        XCTAssertEqual(try stableStore.load(), originalSecret)
    }

    private func makeStore() -> KeychainSecretStore {
        KeychainSecretStore(service: "KeychainSecretStoreTests.\(UUID().uuidString)", account: "api-key")
    }
}
