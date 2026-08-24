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
        let endpoint = try remoteEndpoint()

        try store.save("synthetic-secret", for: endpoint)
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
        let endpoint = try remoteEndpoint()

        try firstStore.save("first", for: endpoint)
        try secondStore.save("second", for: endpoint)
        try firstStore.save("first-updated", for: endpoint)

        XCTAssertEqual(try firstStore.load(for: endpoint), "first-updated")
        XCTAssertEqual(try secondStore.load(for: endpoint), "second")
        try firstStore.delete()
        XCTAssertNil(try firstStore.load(for: endpoint))
        XCTAssertEqual(try secondStore.load(for: endpoint), "second")
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
        let endpoint = try remoteEndpoint()

        try store.save(dummySecret, for: endpoint)
        XCTAssertEqual(try store.load(for: endpoint), dummySecret)

        try store.delete()
        XCTAssertNil(try store.load(for: endpoint))
    }

    func testDeletingMissingSecretSucceeds() throws {
        let keychain = try TemporaryKeychain()
        defer { keychain.delete() }
        let store = KeychainSecretStore(
            service: "KeychainSecretStoreTests.\(UUID().uuidString)",
            account: "api-key",
            keychain: keychain.reference
        )
        let endpoint = try remoteEndpoint()

        try store.delete()

        XCTAssertNil(try store.load(for: endpoint))
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
        let endpoint = try remoteEndpoint()

        try stableStore.save(originalSecret, for: endpoint)
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

        XCTAssertThrowsError(try failingStore.save(UUID().uuidString, for: endpoint)) { error in
            XCTAssertEqual(error as? KeychainSecretStoreError, .unexpectedStatus(errSecAuthFailed))
        }
        XCTAssertEqual(try stableStore.load(for: endpoint), originalSecret)
    }

    func testOnlyMatchingEndpointLoadsAndLegacyDataCanBeReplaced() throws {
        let keychain = try TemporaryKeychain()
        defer { keychain.delete() }
        let service = "KeychainSecretStoreTests.\(UUID().uuidString)"
        let account = "api-key"
        let store = KeychainSecretStore(
            service: service,
            account: account,
            keychain: keychain.reference
        )
        let endpointA = try remoteEndpoint(host: "a.example.test")
        let endpointB = try remoteEndpoint(host: "b.example.test")
        let secretA = UUID().uuidString

        try store.save(secretA, for: endpointA)

        XCTAssertEqual(try store.load(for: endpointA), secretA)
        XCTAssertNil(try store.load(for: endpointB))

        try store.delete()
        let legacyStatus = SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseKeychain as String: keychain.reference,
            kSecValueData as String: Data("legacy-unbound-secret".utf8),
        ] as CFDictionary, nil)
        XCTAssertEqual(legacyStatus, errSecSuccess)
        XCTAssertNil(try store.load(for: endpointA))

        let replacement = UUID().uuidString
        try store.save(replacement, for: endpointA)
        XCTAssertEqual(try store.load(for: endpointA), replacement)
    }

    private func remoteEndpoint(host: String = "example.test") throws -> OrganizationEndpointSettings {
        try OrganizationEndpointSettings(
            baseURL: URL(string: "https://\(host)/v1/chat/completions")!,
            model: "test-model"
        )
    }
}
