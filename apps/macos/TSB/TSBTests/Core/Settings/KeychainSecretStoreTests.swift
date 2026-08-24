import Foundation
import XCTest
@testable import TSB

final class KeychainSecretStoreTests: XCTestCase {
    func testDefaultQueriesKeepProductionIdentityAndDoNotRouteToAnInjectedKeychain() throws {
        var updateQuery: CFDictionary?
        var addQuery: CFDictionary?
        var deleteQuery: CFDictionary?
        let store = KeychainSecretStore(
            update: { query, _ in
                updateQuery = query
                return errSecItemNotFound
            },
            add: { query in
                addQuery = query
                return errSecSuccess
            },
            deleteItem: { query in
                deleteQuery = query
                return errSecSuccess
            }
        )

        try store.save("synthetic-secret")
        try store.delete()

        let queries = try [
            XCTUnwrap(updateQuery),
            XCTUnwrap(addQuery),
            XCTUnwrap(deleteQuery)
        ]
        for query in queries {
            let dictionary = query as NSDictionary
            XCTAssertEqual(dictionary[kSecClass] as? String, kSecClassGenericPassword as String)
            XCTAssertEqual(dictionary[kSecAttrService] as? String, "com.zhuohengchi.tsb")
            XCTAssertEqual(dictionary[kSecAttrAccount] as? String, "organization-api-key")
            XCTAssertNil(dictionary[kSecUseKeychain])
            XCTAssertNil(dictionary[kSecMatchSearchList])
        }
    }

    func testInjectedKeychainsIsolateTheSameServiceAndAccount() throws {
        let firstKeychain = try TemporaryKeychain()
        let secondKeychain = try TemporaryKeychain()
        defer {
            firstKeychain.delete()
            secondKeychain.delete()
        }
        let service = "KeychainSecretStoreTests.shared-service"
        let account = "shared-account"
        let firstStore = KeychainSecretStore(
            service: service,
            account: account,
            keychain: firstKeychain.reference
        )
        let secondStore = KeychainSecretStore(
            service: service,
            account: account,
            keychain: secondKeychain.reference
        )

        try firstStore.save("first")
        try secondStore.save("second")
        try firstStore.save("first-updated")

        XCTAssertEqual(try firstStore.load(), "first-updated")
        XCTAssertEqual(try secondStore.load(), "second")
        try firstStore.delete()
        XCTAssertNil(try firstStore.load())
        XCTAssertEqual(try secondStore.load(), "second")
    }

    func testSaveLoadAndDeleteRoundTrip() throws {
        let keychain = try TemporaryKeychain()
        defer { keychain.delete() }
        let store = KeychainSecretStore(
            service: "KeychainSecretStoreTests.\(UUID().uuidString)",
            account: "api-key",
            keychain: keychain.reference
        )
        let dummySecret = UUID().uuidString

        try store.save(dummySecret)
        XCTAssertEqual(try store.load(), dummySecret)

        try store.delete()
        XCTAssertNil(try store.load())
    }

    func testDeletingMissingSecretSucceeds() throws {
        let keychain = try TemporaryKeychain()
        defer { keychain.delete() }
        let store = KeychainSecretStore(
            service: "KeychainSecretStoreTests.\(UUID().uuidString)",
            account: "api-key",
            keychain: keychain.reference
        )

        try store.delete()

        XCTAssertNil(try store.load())
    }

    func testFailedReplacementPreservesExistingSecret() throws {
        let keychain = try TemporaryKeychain()
        defer { keychain.delete() }
        let service = "KeychainSecretStoreTests.\(UUID().uuidString)"
        let account = "api-key"
        let stableStore = KeychainSecretStore(
            service: service,
            account: account,
            keychain: keychain.reference
        )
        let originalSecret = UUID().uuidString

        try stableStore.save(originalSecret)
        let failingStore = KeychainSecretStore(
            service: service,
            account: account,
            keychain: keychain.reference,
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
}
