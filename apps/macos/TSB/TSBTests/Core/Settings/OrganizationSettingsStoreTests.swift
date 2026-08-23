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
        let secretStore = makeSecretStore()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? secretStore.delete()
        }
        let store = OrganizationSettingsStore(defaults: defaults, secretStore: secretStore)
        let settings = OrganizationSettings(
            endpoint: try remoteEndpoint(),
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
        XCTAssertEqual(try secretStore.load(), dummySecret)
    }

    func testRevokingConsentDisablesDispatchAndDeletesSecret() throws {
        let (defaults, suiteName) = makeDefaults()
        let secretStore = makeSecretStore()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? secretStore.delete()
        }
        let store = OrganizationSettingsStore(defaults: defaults, secretStore: secretStore)
        let settings = OrganizationSettings(
            endpoint: try remoteEndpoint(),
            cloudConsentVersion: OrganizationSettings.currentCloudConsentVersion,
            allowUserSelectedHistorySummaries: true
        )

        try store.save(settings, apiKey: UUID().uuidString)
        try store.revokeCloudConsent()

        XCTAssertFalse(store.load().isRemoteDispatchEligible)
        XCTAssertFalse(store.load().canSendUserSelectedHistorySummaries)
        XCTAssertNil(try secretStore.load())
    }

    func testDeleteRemovesSavedSettingsAndSecret() throws {
        let (defaults, suiteName) = makeDefaults()
        let secretStore = makeSecretStore()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? secretStore.delete()
        }
        let store = OrganizationSettingsStore(defaults: defaults, secretStore: secretStore)
        let settings = OrganizationSettings(
            endpoint: try remoteEndpoint(),
            cloudConsentVersion: OrganizationSettings.currentCloudConsentVersion
        )

        try store.save(settings, apiKey: UUID().uuidString)
        try store.delete()

        XCTAssertEqual(store.load(), OrganizationSettings())
        XCTAssertNil(try secretStore.load())
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

    private func makeSecretStore() -> KeychainSecretStore {
        KeychainSecretStore(service: "OrganizationSettingsStoreTests.\(UUID().uuidString)", account: "api-key")
    }
}
