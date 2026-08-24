import Foundation
import XCTest
@testable import TSB

final class OrganizationSettingsStoreTests: XCTestCase {
    func testRemoteDispatchRequiresCurrentConsent() throws {
        let endpoint = try remoteEndpoint()

        XCTAssertFalse(OrganizationSettings(endpoint: endpoint).isRemoteDispatchEligible)
        XCTAssertFalse(OrganizationSettings(endpoint: endpoint, cloudConsentVersion: 0).isRemoteDispatchEligible)
        XCTAssertTrue(
            OrganizationSettings(
                endpoint: endpoint,
                cloudConsentVersion: OrganizationSettings.currentCloudConsentVersion
            ).isRemoteDispatchEligible
        )
    }

    func testConsentVersionMatchesOrganizationRequestContract() {
        XCTAssertEqual(OrganizationSettings.currentCloudConsentVersion, OrganizationRequestContract.consentVersion)
        XCTAssertEqual(OrganizationRequestContract.schemaVersion, "tsb.organization.request.v1")
    }

    func testHistorySummariesRequireSeparateConsent() throws {
        let endpoint = try remoteEndpoint()
        let withoutHistoryConsent = OrganizationSettings(
            endpoint: endpoint,
            cloudConsentVersion: OrganizationSettings.currentCloudConsentVersion
        )
        let withHistoryConsent = OrganizationSettings(
            endpoint: endpoint,
            cloudConsentVersion: OrganizationSettings.currentCloudConsentVersion,
            allowUserSelectedHistorySummaries: true
        )

        XCTAssertFalse(withoutHistoryConsent.canSendUserSelectedHistorySummaries)
        XCTAssertTrue(withHistoryConsent.canSendUserSelectedHistorySummaries)
    }

    func testLoadRestoresSavedSettingsWithoutEncodingAPIKey() throws {
        let (defaults, suiteName) = makeDefaults()
        let keychain = try TemporaryKeychain()
        let secretStore = makeSecretStore(keychain: keychain.reference)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            keychain.delete()
        }
        let store = OrganizationSettingsStore(defaults: defaults, secretStore: secretStore)
        let endpoint = try remoteEndpoint()
        let settings = OrganizationSettings(
            endpoint: endpoint,
            cloudConsentVersion: OrganizationSettings.currentCloudConsentVersion,
            allowUserSelectedHistorySummaries: true
        )
        let dummySecret = UUID().uuidString

        try store.save(settings, apiKey: dummySecret)

        let reloadedStore = OrganizationSettingsStore(defaults: defaults, secretStore: secretStore)
        XCTAssertEqual(reloadedStore.load(), settings)
        let encodedSettings = try XCTUnwrap(defaults.data(forKey: OrganizationSettingsStore.storageKey))
        XCTAssertFalse(String(decoding: encodedSettings, as: UTF8.self).contains(dummySecret))
        let persistedDefaults = defaults.persistentDomain(forName: suiteName) ?? [:]
        XCTAssertFalse(persistedDefaults.values.contains {
            ($0 as? String)?.contains(dummySecret) == true
                || ($0 as? Data).map { String(decoding: $0, as: UTF8.self).contains(dummySecret) } == true
        })
        XCTAssertEqual(try secretStore.load(for: endpoint), dummySecret)
    }

    func testRevokingConsentDisablesDispatchAndDeletesSecret() throws {
        let (defaults, suiteName) = makeDefaults()
        let keychain = try TemporaryKeychain()
        let secretStore = makeSecretStore(keychain: keychain.reference)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            keychain.delete()
        }
        let store = OrganizationSettingsStore(defaults: defaults, secretStore: secretStore)
        let endpoint = try remoteEndpoint()
        let settings = OrganizationSettings(
            endpoint: endpoint,
            cloudConsentVersion: OrganizationSettings.currentCloudConsentVersion,
            allowUserSelectedHistorySummaries: true
        )

        try store.save(settings, apiKey: UUID().uuidString)
        try store.revokeCloudConsent()

        XCTAssertFalse(store.load().isRemoteDispatchEligible)
        XCTAssertFalse(store.load().canSendUserSelectedHistorySummaries)
        XCTAssertNil(try secretStore.load(for: endpoint))
    }

    func testDeleteRemovesSavedSettingsAndSecret() throws {
        let (defaults, suiteName) = makeDefaults()
        let keychain = try TemporaryKeychain()
        let secretStore = makeSecretStore(keychain: keychain.reference)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            keychain.delete()
        }
        let store = OrganizationSettingsStore(defaults: defaults, secretStore: secretStore)
        let endpoint = try remoteEndpoint()
        let settings = OrganizationSettings(
            endpoint: endpoint,
            cloudConsentVersion: OrganizationSettings.currentCloudConsentVersion
        )

        try store.save(settings, apiKey: UUID().uuidString)
        try store.delete()

        XCTAssertEqual(store.load(), OrganizationSettings())
        XCTAssertNil(try secretStore.load(for: endpoint))
    }

    func testRejectsNonLoopbackHTTPRemoteEndpoint() {
        XCTAssertThrowsError(
            try OrganizationEndpointSettings(
                baseURL: URL(string: "http://example.test/v1/chat/completions")!,
                model: "test-model"
            )
        ) { error in
            XCTAssertEqual(error as? OrganizationEndpointSettingsError, .insecureEndpoint)
        }
    }

    func testAllowsLoopbackHTTPRemoteEndpoint() throws {
        let endpoint = try OrganizationEndpointSettings(
            baseURL: URL(string: "http://127.0.0.1:11434/v1/chat/completions")!,
            model: "local-model"
        )

        XCTAssertTrue(endpoint.isLoopback)
    }

    func testRejectsEndpointCredentialsAndFragments() {
        for rawURL in [
            "https://user@example.test/v1/chat/completions",
            "https://user:password@example.test/v1/chat/completions",
            "https://example.test/v1/chat/completions#private",
        ] {
            XCTAssertThrowsError(
                try OrganizationEndpointSettings(
                    baseURL: URL(string: rawURL)!,
                    model: "test-model"
                ),
                rawURL
            ) { error in
                XCTAssertEqual(error as? OrganizationEndpointSettingsError, .insecureEndpoint)
            }
        }
    }

    func testLoadRejectsPersistedEndpointUserInfoAndFragments() throws {
        for rawURL in [
            "https://user@example.test/v1/chat/completions",
            "https://example.test/v1/chat/completions#private",
        ] {
            let (defaults, suiteName) = makeDefaults()
            let keychain = try TemporaryKeychain()
            defer {
                defaults.removePersistentDomain(forName: suiteName)
                keychain.delete()
            }
            let store = OrganizationSettingsStore(
                defaults: defaults,
                secretStore: makeSecretStore(keychain: keychain.reference)
            )
            let persisted = try JSONSerialization.data(withJSONObject: [
                "endpoint": ["baseURL": rawURL, "model": "test-model"],
                "cloudConsentVersion": OrganizationSettings.currentCloudConsentVersion,
                "allowUserSelectedHistorySummaries": true,
            ])
            defaults.set(persisted, forKey: OrganizationSettingsStore.storageKey)

            XCTAssertEqual(store.load(), OrganizationSettings(), rawURL)
        }
    }

    private func remoteEndpoint() throws -> OrganizationEndpointSettings {
        try OrganizationEndpointSettings(
            baseURL: URL(string: "https://example.test/v1/chat/completions")!,
            model: "test-model"
        )
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "OrganizationSettingsStoreTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func makeSecretStore(keychain: SecKeychain) -> KeychainSecretStore {
        KeychainSecretStore(
            service: "OrganizationSettingsStoreTests.\(UUID().uuidString)",
            account: "api-key",
            keychain: keychain
        )
    }
}
