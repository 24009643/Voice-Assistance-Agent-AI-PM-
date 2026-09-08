import AppKit
import Foundation
import Security
import XCTest
@testable import TSB

@MainActor
final class SettingsBehaviorTests: XCTestCase {
    func testLaunchModelCanSkipPersistedUserState() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try fixture.store.save(
            try remoteSettings(model: "persisted-model"),
            apiKey: UUID().uuidString
        )

        let model = SettingsModel(store: fixture.store, loadPersistedState: false)

        XCTAssertEqual(model.draft, SettingsDraft())
        XCTAssertFalse(model.hasPersistedAPIKey)
        XCTAssertNil(model.errorMessage)
    }

    func testSuccessfulPolishRevokeInvokesPendingDeliveryCancellationOnce() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let endpoint = try OrganizationEndpointSettings(
            baseURL: URL(string: "https://example.test/v1/chat/completions")!,
            model: "polish-model"
        )
        try fixture.store.save(OrganizationSettings(
            endpoint: endpoint,
            polishEnabled: true,
            polishConsentVersion: OrganizationSettings.currentPolishConsentVersion
        ), apiKey: UUID().uuidString)
        var cancellations = 0
        let model = TSBAppDelegate.makeSettingsModel(
            store: fixture.store,
            cancelPendingPolish: { cancellations += 1 }
        )

        model.revokePolishAccess()

        XCTAssertEqual(model.status, .polishRevoked)
        XCTAssertEqual(cancellations, 1)
        XCTAssertFalse(fixture.store.load().isPolishDispatchEligible)
    }

    func testPolishRevokeKeyDeletionFailureStillCancelsPendingDeliveryOnce() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let endpoint = try OrganizationEndpointSettings(
            baseURL: URL(string: "https://example.test/v1/chat/completions")!,
            model: "polish-model"
        )
        let originalSecret = UUID().uuidString
        try fixture.store.save(OrganizationSettings(
            endpoint: endpoint,
            polishEnabled: true,
            polishConsentVersion: OrganizationSettings.currentPolishConsentVersion
        ), apiKey: originalSecret)
        let failingStore = OrganizationSettingsStore(
            defaults: fixture.defaults,
            secretStore: KeychainSecretStore(
                service: fixture.service,
                account: fixture.account,
                keychain: fixture.keychain.reference,
                deleteItem: { _ in errSecAuthFailed }
            )
        )
        var cancellations = 0
        let model = SettingsModel(
            store: failingStore,
            onPolishAccessRevoked: { cancellations += 1 }
        )

        model.revokePolishAccess()

        XCTAssertNil(model.status)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(cancellations, 1)
        XCTAssertFalse(fixture.store.load().isPolishDispatchEligible)
        XCTAssertEqual(try fixture.secretStore.load(for: endpoint), originalSecret)
    }

    func testRemoteSaveRequiresConfirmedConsentAndLaterDispatchUsesPersistedConsent() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let model = SettingsModel(store: fixture.store)
        let dummySecret = UUID().uuidString
        model.draft.baseURL = "https://example.test/v1/chat/completions"
        model.draft.model = "test-model"
        model.draft.apiKey = dummySecret

        model.save()

        XCTAssertEqual(fixture.store.load(), OrganizationSettings())
        XCTAssertThrowsError(try AppController.makeOrganizationDispatchSnapshot(
            selectedCandidateIDs: [],
            loadSettings: fixture.store.load,
            loadAPIKey: { try fixture.secretStore.load(for: $0) }
        ))

        model.confirmCloudConsent()
        model.save()

        XCTAssertEqual(model.status, .saved)
        let nextSettingsSession = SettingsModel(store: fixture.store)
        XCTAssertTrue(nextSettingsSession.draft.cloudConsent)
        XCTAssertNoThrow(try AppController.makeOrganizationDispatchSnapshot(
            selectedCandidateIDs: [],
            loadSettings: fixture.store.load,
            loadAPIKey: { try fixture.secretStore.load(for: $0) }
        ))
    }

    func testSelectedHistoryStillRequiresItsSeparateConsentAfterCloudConsent() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let model = SettingsModel(store: fixture.store)
        model.draft.baseURL = "https://example.test/v1/chat/completions"
        model.draft.model = "test-model"
        model.draft.apiKey = UUID().uuidString
        model.confirmCloudConsent()
        model.save()

        XCTAssertThrowsError(try AppController.makeOrganizationDispatchSnapshot(
            selectedCandidateIDs: ["h1"],
            loadSettings: fixture.store.load,
            loadAPIKey: { try fixture.secretStore.load(for: $0) }
        ))

        model.draft.allowSelectedHistorySummaries = true
        model.save()

        XCTAssertNoThrow(try AppController.makeOrganizationDispatchSnapshot(
            selectedCandidateIDs: ["h1"],
            loadSettings: fixture.store.load,
            loadAPIKey: { try fixture.secretStore.load(for: $0) }
        ))
    }

    func testBlankKeyPreservesAnExistingSecretOnSave() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let originalSecret = UUID().uuidString
        let settings = try remoteSettings(model: "old-model")
        try fixture.store.save(settings, apiKey: originalSecret)
        let model = SettingsModel(store: fixture.store)
        model.draft.model = "new-model"
        model.draft.apiKey = "   "

        model.save()

        XCTAssertEqual(model.status, .saved)
        XCTAssertEqual(fixture.store.load().endpoint?.model, "new-model")
        XCTAssertEqual(try fixture.secretStore.load(for: settings.endpoint!), originalSecret)
        XCTAssertTrue(model.hasPersistedAPIKey)
        XCTAssertTrue(model.draft.apiKey.isEmpty)
    }

    func testBlankKeyCannotReuseAnExistingSecretForAChangedEndpoint() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let originalSecret = UUID().uuidString
        let originalSettings = try remoteSettings(model: "old-model")
        try fixture.store.save(originalSettings, apiKey: originalSecret)
        let model = SettingsModel(store: fixture.store)
        model.draft.baseURL = "https://changed.example.test/v1/chat/completions"
        model.draft.model = "new-model"
        model.draft.apiKey = "   "

        model.save()

        XCTAssertEqual(fixture.store.load(), originalSettings)
        XCTAssertEqual(try fixture.secretStore.load(for: originalSettings.endpoint!), originalSecret)
        let changedEndpoint = try OrganizationEndpointSettings(
            baseURL: URL(string: model.draft.baseURL)!,
            model: model.draft.model
        )
        XCTAssertNil(try fixture.secretStore.load(for: changedEndpoint))
    }

    func testDispatchRejectsMissingLegacyAndWrongEndpointSecrets() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let endpointA = try remoteSettings(baseURL: "https://a.example.test/v1/chat/completions")
        let endpointB = try remoteSettings(baseURL: "https://b.example.test/v1/chat/completions")

        XCTAssertThrowsError(try AppController.makeOrganizationDispatchSnapshot(
            selectedCandidateIDs: [],
            loadSettings: { endpointA },
            loadAPIKey: { _ in nil }
        ))

        try fixture.saveLegacySecret("legacy-unbound-secret")
        XCTAssertThrowsError(try AppController.makeOrganizationDispatchSnapshot(
            selectedCandidateIDs: [],
            loadSettings: { endpointA },
            loadAPIKey: { try fixture.secretStore.load(for: $0) }
        ))

        try fixture.secretStore.save("synthetic-key-for-b", for: endpointB.endpoint!)
        XCTAssertThrowsError(try AppController.makeOrganizationDispatchSnapshot(
            selectedCandidateIDs: [],
            loadSettings: { endpointA },
            loadAPIKey: { try fixture.secretStore.load(for: $0) }
        ))

        XCTAssertNoThrow(try AppController.makeOrganizationDispatchSnapshot(
            selectedCandidateIDs: [],
            loadSettings: { endpointB },
            loadAPIKey: { try fixture.secretStore.load(for: $0) }
        ))
    }

    func testInterruptedEndpointChangeCannotDispatchTheNewBindingWithOldSettings() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let endpointA = try remoteSettings(baseURL: "https://a.example.test/v1/chat/completions")
        let endpointB = try remoteSettings(baseURL: "https://b.example.test/v1/chat/completions")
        try fixture.store.save(endpointA, apiKey: "synthetic-key-for-a")
        try fixture.secretStore.save("synthetic-key-for-b", for: endpointB.endpoint!)

        XCTAssertEqual(fixture.store.load(), endpointA)
        XCTAssertThrowsError(try AppController.makeOrganizationDispatchSnapshot(
            selectedCandidateIDs: [],
            loadSettings: fixture.store.load,
            loadAPIKey: { try fixture.secretStore.load(for: $0) }
        ))
    }

    func testFailedKeyReplacementKeepsTheOldProfileAndSecret() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let originalSecret = UUID().uuidString
        let originalSettings = try remoteSettings(model: "old-model")
        try fixture.store.save(originalSettings, apiKey: originalSecret)
        let failingSecretStore = KeychainSecretStore(
            service: fixture.service,
            account: fixture.account,
            keychain: fixture.keychain.reference,
            update: { _, _ in errSecAuthFailed },
            add: { _ in
                XCTFail("An existing secret replacement must not add")
                return errSecSuccess
            }
        )
        let model = SettingsModel(store: OrganizationSettingsStore(
            defaults: fixture.defaults,
            secretStore: failingSecretStore
        ))
        model.draft.model = "new-model"
        model.draft.apiKey = UUID().uuidString

        model.save()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(fixture.store.load(), originalSettings)
        XCTAssertEqual(try fixture.secretStore.load(for: originalSettings.endpoint!), originalSecret)
    }

    func testLoopbackSaveCommitsOnlyAfterSecretDeletionAndCanRetry() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let originalSecret = UUID().uuidString
        let originalSettings = try remoteSettings(model: "remote-model", historyConsent: true)
        try fixture.store.save(originalSettings, apiKey: originalSecret)
        let failingStore = OrganizationSettingsStore(
            defaults: fixture.defaults,
            secretStore: KeychainSecretStore(
                service: fixture.service,
                account: fixture.account,
                keychain: fixture.keychain.reference,
                deleteItem: { _ in errSecAuthFailed }
            )
        )
        let model = SettingsModel(store: failingStore)
        model.draft.baseURL = "http://127.0.0.1:11434/v1/chat/completions"
        model.draft.model = "local-model"

        model.save()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(fixture.store.load(), originalSettings)
        XCTAssertTrue(fixture.store.load().isRemoteDispatchEligible)
        XCTAssertTrue(fixture.store.load().canSendUserSelectedHistorySummaries)
        XCTAssertEqual(try fixture.secretStore.load(for: originalSettings.endpoint!), originalSecret)
        XCTAssertTrue(model.hasPersistedAPIKey)

        let retry = SettingsModel(store: fixture.store)
        retry.draft.baseURL = "http://127.0.0.1:11434/v1/chat/completions"
        retry.draft.model = "local-model"
        retry.save()

        XCTAssertEqual(retry.status, .saved)
        XCTAssertEqual(fixture.store.load().endpoint?.model, "local-model")
        XCTAssertTrue(fixture.store.load().endpoint?.isLoopback == true)
        XCTAssertFalse(fixture.store.load().isRemoteDispatchEligible)
        XCTAssertFalse(fixture.store.load().canSendUserSelectedHistorySummaries)
        XCTAssertNil(try fixture.secretStore.load(for: originalSettings.endpoint!))
    }

    func testCancelReloadsPersistedDraftWithoutAnyWrite() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let originalSecret = UUID().uuidString
        let originalSettings = try remoteSettings(model: "persisted-model", historyConsent: true)
        try fixture.store.save(originalSettings, apiKey: originalSecret)
        let writeRejectingSecretStore = KeychainSecretStore(
            service: fixture.service,
            account: fixture.account,
            keychain: fixture.keychain.reference,
            update: { _, _ in
                XCTFail("Cancel must not update Keychain")
                return errSecAuthFailed
            },
            add: { _ in
                XCTFail("Cancel must not add to Keychain")
                return errSecAuthFailed
            },
            deleteItem: { _ in
                XCTFail("Cancel must not delete from Keychain")
                return errSecAuthFailed
            }
        )
        let model = SettingsModel(store: OrganizationSettingsStore(
            defaults: fixture.defaults,
            secretStore: writeRejectingSecretStore
        ))
        let defaultsBefore = fixture.defaults.persistentDomain(forName: fixture.suiteName)
        model.draft.baseURL = "https://changed.test/v1/chat/completions"
        model.draft.model = "changed-model"
        model.draft.apiKey = UUID().uuidString
        model.draft.cloudConsent = false
        model.draft.allowSelectedHistorySummaries = false

        model.cancel()

        XCTAssertNil(model.status)
        XCTAssertEqual(model.draft.baseURL, originalSettings.endpoint?.baseURL.absoluteString)
        XCTAssertEqual(model.draft.model, "persisted-model")
        XCTAssertTrue(model.draft.apiKey.isEmpty)
        XCTAssertTrue(model.draft.cloudConsent)
        XCTAssertTrue(model.draft.allowSelectedHistorySummaries)
        XCTAssertTrue(model.hasPersistedAPIKey)
        XCTAssertEqual(fixture.defaults.persistentDomain(forName: fixture.suiteName) as NSDictionary?, defaultsBefore as NSDictionary?)
        XCTAssertEqual(try fixture.secretStore.load(for: originalSettings.endpoint!), originalSecret)
    }

    func testDeleteFailureIsVisibleAndNeverClaimsDeletion() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let originalSecret = UUID().uuidString
        var settings = try remoteSettings(historyConsent: true)
        settings.polishEnabled = true
        settings.polishConsentVersion = OrganizationSettings.currentPolishConsentVersion
        try fixture.store.save(settings, apiKey: originalSecret)
        let failingSecretStore = KeychainSecretStore(
            service: fixture.service,
            account: fixture.account,
            keychain: fixture.keychain.reference,
            deleteItem: { _ in errSecAuthFailed }
        )
        var cancellations = 0
        let model = SettingsModel(
            store: OrganizationSettingsStore(
                defaults: fixture.defaults,
                secretStore: failingSecretStore
            ),
            onPolishAccessRevoked: { cancellations += 1 }
        )

        model.deleteProfile()

        let blockedSettings = fixture.store.load()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(blockedSettings.endpoint, settings.endpoint)
        XCTAssertFalse(blockedSettings.isRemoteDispatchEligible)
        XCTAssertFalse(blockedSettings.canSendUserSelectedHistorySummaries)
        XCTAssertFalse(blockedSettings.isPolishDispatchEligible)
        XCTAssertEqual(cancellations, 1)
        XCTAssertTrue(model.hasPersistedAPIKey)
        XCTAssertEqual(try fixture.secretStore.load(for: settings.endpoint!), originalSecret)
        XCTAssertThrowsError(try AppController.makeOrganizationDispatchSnapshot(
            selectedCandidateIDs: [],
            loadSettings: fixture.store.load,
            loadAPIKey: { try fixture.secretStore.load(for: $0) }
        ))

        let retry = SettingsModel(store: fixture.store)
        XCTAssertEqual(retry.draft.baseURL, settings.endpoint?.baseURL.absoluteString)
        XCTAssertFalse(retry.draft.cloudConsent)
        XCTAssertFalse(retry.draft.allowSelectedHistorySummaries)
        XCTAssertTrue(retry.hasPersistedAPIKey)
        retry.deleteProfile()

        XCTAssertEqual(retry.status, .deleted)
        XCTAssertFalse(retry.hasPersistedAPIKey)
        XCTAssertNil(try fixture.secretStore.load(for: settings.endpoint!))
    }

    func testPersistedEndpointUserInfoAndFragmentsCannotSurfaceThroughSettingsModel() throws {
        for rawURL in [
            "https://user@example.test/v1/chat/completions",
            "https://example.test/v1/chat/completions#private",
        ] {
            let fixture = try makeFixture()
            defer { fixture.cleanup() }
            let persisted = try JSONSerialization.data(withJSONObject: [
                "endpoint": ["baseURL": rawURL, "model": "test-model"],
                "cloudConsentVersion": OrganizationSettings.currentCloudConsentVersion,
                "allowUserSelectedHistorySummaries": true,
            ])
            fixture.defaults.set(persisted, forKey: OrganizationSettingsStore.storageKey)

            let model = SettingsModel(store: fixture.store)

            XCTAssertEqual(fixture.store.load(), OrganizationSettings(), rawURL)
            XCTAssertTrue(model.draft.baseURL.isEmpty, rawURL)
            XCTAssertTrue(model.draft.model.isEmpty, rawURL)
            XCTAssertFalse(model.draft.cloudConsent, rawURL)
            XCTAssertFalse(model.draft.allowSelectedHistorySummaries, rawURL)
            XCTAssertFalse(model.hasPersistedAPIKey, rawURL)
        }
    }

    func testDeleteRemovesProfileAndKeyBeforeClaimingSuccess() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        var settings = try remoteSettings(historyConsent: true)
        settings.polishEnabled = true
        settings.polishConsentVersion = OrganizationSettings.currentPolishConsentVersion
        try fixture.store.save(settings, apiKey: UUID().uuidString)
        var cancellations = 0
        let model = SettingsModel(
            store: fixture.store,
            onPolishAccessRevoked: { cancellations += 1 }
        )

        model.deleteProfile()

        XCTAssertEqual(model.status, .deleted)
        XCTAssertEqual(fixture.store.load(), OrganizationSettings())
        XCTAssertFalse(model.draft.cloudConsent)
        XCTAssertFalse(model.draft.allowSelectedHistorySummaries)
        XCTAssertFalse(model.hasPersistedAPIKey)
        XCTAssertEqual(cancellations, 1)
        XCTAssertNil(try fixture.secretStore.load(for: remoteSettings().endpoint!))
    }

    func testRevokeClearsBothConsentsAndDeletesTheSecret() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try fixture.store.save(
            try remoteSettings(historyConsent: true),
            apiKey: UUID().uuidString
        )
        let model = SettingsModel(store: fixture.store)

        model.revokeCloudAccess()

        XCTAssertEqual(model.status, .revoked)
        XCTAssertFalse(model.draft.cloudConsent)
        XCTAssertFalse(model.draft.allowSelectedHistorySummaries)
        XCTAssertFalse(model.hasPersistedAPIKey)
        XCTAssertNil(try fixture.secretStore.load(for: remoteSettings().endpoint!))
        XCTAssertNotNil(fixture.store.load().endpoint)
    }

    func testRevokeDeleteFailureBlocksDispatchWhileKeepingEndpointAndKeyRetryable() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let originalSecret = UUID().uuidString
        let originalSettings = try remoteSettings(model: "remote-model", historyConsent: true)
        try fixture.store.save(originalSettings, apiKey: originalSecret)
        let failingStore = OrganizationSettingsStore(
            defaults: fixture.defaults,
            secretStore: KeychainSecretStore(
                service: fixture.service,
                account: fixture.account,
                keychain: fixture.keychain.reference,
                deleteItem: { _ in errSecAuthFailed }
            )
        )
        let model = SettingsModel(store: failingStore)

        model.revokeCloudAccess()

        let revokedSettings = fixture.store.load()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(revokedSettings.endpoint, originalSettings.endpoint)
        XCTAssertFalse(revokedSettings.isRemoteDispatchEligible)
        XCTAssertFalse(revokedSettings.canSendUserSelectedHistorySummaries)
        XCTAssertTrue(model.hasPersistedAPIKey)
        XCTAssertEqual(try fixture.secretStore.load(for: originalSettings.endpoint!), originalSecret)
        XCTAssertThrowsError(try AppController.makeOrganizationDispatchSnapshot(
            selectedCandidateIDs: [],
            loadSettings: fixture.store.load,
            loadAPIKey: { try fixture.secretStore.load(for: $0) }
        ))

        let retry = SettingsModel(store: fixture.store)
        retry.revokeCloudAccess()

        XCTAssertEqual(retry.status, .revoked)
        XCTAssertEqual(fixture.store.load().endpoint, originalSettings.endpoint)
        XCTAssertFalse(fixture.store.load().isRemoteDispatchEligible)
        XCTAssertFalse(retry.hasPersistedAPIKey)
        XCTAssertNil(try fixture.secretStore.load(for: originalSettings.endpoint!))
    }

    func testLoopbackHTTPSemanticsDoNotRequireCloudConsentOrAKey() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let model = SettingsModel(store: fixture.store)
        model.draft.baseURL = "http://127.0.0.1:11434/v1/chat/completions"
        model.draft.model = "local-model"

        model.save()

        XCTAssertEqual(model.status, .saved)
        let dispatch = try AppController.makeOrganizationDispatchSnapshot(
            selectedCandidateIDs: [],
            loadSettings: fixture.store.load,
            loadAPIKey: { _ in
                XCTFail("Loopback dispatch must not load Keychain")
                return nil
            }
        )
        XCTAssertEqual(dispatch.apiKey, "")
    }

    func testLocalOnlyDispatchSnapshotFallsBackBeforeLoadingARemoteSecret() throws {
        let settings = try remoteSettings()
        var secretLoadCount = 0

        XCTAssertThrowsError(try AppController.makeOrganizationDispatchSnapshot(
            localOnly: true,
            selectedCandidateIDs: [],
            loadSettings: { settings },
            loadAPIKey: { _ in
                secretLoadCount += 1
                return "must-not-load"
            }
        )) { error in
            guard let error = error as? OrganizationDispatchError,
                  case .deterministicFallback = error else {
                return XCTFail("Expected deterministic fallback")
            }
        }
        XCTAssertEqual(secretLoadCount, 0)
    }

    func testPolishDispatchUsesNoKeyForLoopbackAndLocalOnlyFallsBackFirst() async throws {
        let endpoint = try OrganizationEndpointSettings(
            baseURL: URL(string: "http://127.0.0.1:11434/v1/chat/completions")!,
            model: "local-model"
        )
        let loopback = OrganizationSettings(endpoint: endpoint, polishEnabled: true)
        var loopbackSecretLoadCount = 0

        let dispatch = try await AppController.makePolishDispatchSnapshot(
            loadSettings: { loopback },
            loadAPIKey: { _ in
                loopbackSecretLoadCount += 1
                return nil
            }
        )
        XCTAssertEqual(dispatch.apiKey, "")
        XCTAssertEqual(loopbackSecretLoadCount, 0)

        var secretLoadCount = 0
        let remote = try remoteSettings()
        do {
            _ = try await AppController.makePolishDispatchSnapshot(
                localOnly: true,
                loadSettings: { remote },
                loadAPIKey: { _ in
                    secretLoadCount += 1
                    return "must-not-load"
                }
            )
            XCTFail("expected local-only fallback")
        } catch {
            XCTAssertEqual(error as? TranscriptPolishDispatchError, .notEligible)
        }
        XCTAssertEqual(secretLoadCount, 0)
    }

    func testPolishDispatchLoadsTheEndpointBoundRemoteSecretExactlyOnce() async throws {
        let endpoint = try OrganizationEndpointSettings(
            baseURL: URL(string: "https://api.example.test/v1/chat/completions")!,
            model: "remote-model"
        )
        let remote = OrganizationSettings(
            endpoint: endpoint,
            cloudConsentVersion: OrganizationSettings.currentCloudConsentVersion,
            polishEnabled: true,
            polishConsentVersion: OrganizationSettings.currentPolishConsentVersion
        )
        var secretLoadCount = 0

        let dispatch = try await AppController.makePolishDispatchSnapshot(
            loadSettings: { remote },
            loadAPIKey: { loadedEndpoint in
                secretLoadCount += 1
                XCTAssertEqual(loadedEndpoint, endpoint)
                return "endpoint-bound-key"
            }
        )

        XCTAssertEqual(dispatch.apiKey, "endpoint-bound-key")
        XCTAssertEqual(secretLoadCount, 1)
    }

    func testRemoteHTTPIsRejectedWithoutChangingPersistence() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let model = SettingsModel(store: fixture.store)
        model.draft.baseURL = "http://example.test/v1/chat/completions"
        model.draft.model = "test-model"
        model.draft.apiKey = UUID().uuidString
        model.confirmCloudConsent()

        model.save()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(fixture.store.load(), OrganizationSettings())
    }

    func testEndpointCredentialsAndFragmentsFailWithoutChangingSettingsOrKeychain() throws {
        for rawURL in [
            "https://user:password@example.test/v1/chat/completions",
            "https://example.test/v1/chat/completions#private",
        ] {
            let fixture = try makeFixture()
            defer { fixture.cleanup() }
            let originalSecret = UUID().uuidString
            let originalSettings = try remoteSettings(model: "old-model")
            try fixture.store.save(originalSettings, apiKey: originalSecret)
            let model = SettingsModel(store: fixture.store)
            model.draft.baseURL = rawURL
            model.draft.model = "new-model"
            model.draft.apiKey = UUID().uuidString

            model.save()

            XCTAssertEqual(fixture.store.load(), originalSettings, rawURL)
            XCTAssertEqual(try fixture.secretStore.load(for: originalSettings.endpoint!), originalSecret, rawURL)
        }
    }

    func testAppDelegateStartsAtLaunchAndStopsOnlyAtTermination() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        var starts = 0
        var stops = 0
        let delegate = TSBAppDelegate(
            controller: AppController(),
            settingsModel: SettingsModel(store: fixture.store),
            startController: { starts += 1 },
            stopController: { stops += 1 }
        )

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertEqual(starts, 1)
        XCTAssertEqual(stops, 0)

        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        XCTAssertEqual(starts, 1)
        XCTAssertEqual(stops, 1)
    }

    private func remoteSettings(
        baseURL: String = "https://example.test/v1/chat/completions",
        model: String = "test-model",
        historyConsent: Bool = false
    ) throws -> OrganizationSettings {
        OrganizationSettings(
            endpoint: try OrganizationEndpointSettings(
                baseURL: URL(string: baseURL)!,
                model: model
            ),
            cloudConsentVersion: OrganizationSettings.currentCloudConsentVersion,
            allowUserSelectedHistorySummaries: historyConsent
        )
    }

    private func makeFixture() throws -> SettingsFixture {
        let suiteName = "SettingsBehaviorTests.\(UUID().uuidString)"
        let service = "SettingsBehaviorTests.\(UUID().uuidString)"
        let account = "api-key"
        let defaults = UserDefaults(suiteName: suiteName)!
        let keychain = try TemporaryKeychain()
        let secretStore = KeychainSecretStore(
            service: service,
            account: account,
            keychain: keychain.reference
        )
        return SettingsFixture(
            suiteName: suiteName,
            service: service,
            account: account,
            defaults: defaults,
            keychain: keychain,
            secretStore: secretStore,
            store: OrganizationSettingsStore(defaults: defaults, secretStore: secretStore)
        )
    }
}

private struct SettingsFixture {
    let suiteName: String
    let service: String
    let account: String
    let defaults: UserDefaults
    let keychain: TemporaryKeychain
    let secretStore: KeychainSecretStore
    let store: OrganizationSettingsStore

    func saveLegacySecret(_ secret: String) throws {
        let status = SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseKeychain as String: keychain.reference,
            kSecValueData as String: Data(secret.utf8),
        ] as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        keychain.delete()
    }
}
