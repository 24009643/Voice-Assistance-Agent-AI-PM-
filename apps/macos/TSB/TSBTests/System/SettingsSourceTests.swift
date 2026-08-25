import AppKit
import Foundation
import Security
import XCTest
@testable import TSB

final class SettingsSourceTests: XCTestCase {
    func testFullWindowContainsOnlySettingsAndAppDelegateOwnsLaunch() throws {
        let appSource = try source("TSB/App/TSBApp.swift")
        let delegateSource = try source("TSB/App/TSBAppDelegate.swift")
        let menuSource = try source("TSB/Views/MenuBarView.swift")

        XCTAssertTrue(appSource.contains("NSApplicationDelegateAdaptor"))
        XCTAssertTrue(appSource.contains("Settings {"))
        XCTAssertTrue(appSource.contains("SettingsView("))
        XCTAssertTrue(appSource.contains("MenuBarExtra"))
        XCTAssertTrue(menuSource.contains("⌥Space"))
        XCTAssertTrue(menuSource.contains("开始录音"))
        XCTAssertTrue(menuSource.contains("停止录音"))
        XCTAssertTrue(menuSource.contains("取消录音"))
        XCTAssertTrue(menuSource.contains("SettingsLink"))
        XCTAssertTrue(menuSource.contains("退出 TSB"))
        XCTAssertTrue(menuSource.contains("打开麦克风设置"))
        XCTAssertTrue(menuSource.contains("openMicrophoneSettings"))
        XCTAssertTrue(menuSource.contains("state.snapshot.message == \"Microphone access is required to record.\""))
        XCTAssertFalse(menuSource.contains("coordinator"))
        XCTAssertFalse(menuSource.contains("recorder"))
        XCTAssertFalse(appSource.contains("WindowGroup"))
        XCTAssertFalse(appSource.contains("PlaceholderView"))
        XCTAssertFalse(appSource.contains("onDisappear"))
        XCTAssertTrue(delegateSource.contains("AppController"))
        XCTAssertTrue(delegateSource.contains("applicationDidFinishLaunching"))
        XCTAssertTrue(delegateSource.contains("controller.start()"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL("TSB/Views/PlaceholderView.swift").path))
    }

    func testSettingsSourceExposesTheRequiredFieldsActionsAndConsentCopy() throws {
        let settingsSource = try source("TSB/Views/SettingsView.swift")

        for required in [
            "OpenAI-compatible", "完整 Chat Completions 接口地址", "https://api.example.com/v1/chat/completions",
            "Model", "SecureField", "已保存配置的 API Key", "未保存",
            "保存", "取消", "撤销云端授权", "删除配置与密钥", "出站预览",
            "当前文本", "TSB 历史摘要", "音频", "文件路径", "完整记忆库",
            "不会覆盖剪贴板", "仅本地", "另行授权",
            "撤销云端整理授权", "已撤销云端整理授权。",
            "文本润色授权", "查看润色授权范围", "撤销文本润色授权",
            "已确认，保存后启用", "音频、录音历史、文件路径和完整记忆库不会发送",
            "最多会让剪贴板交付额外等待 1.5 秒", "无法撤回已发送的文本",
        ] {
            XCTAssertTrue(settingsSource.contains(required), "Missing settings boundary: \(required)")
        }
        XCTAssertFalse(settingsSource.contains("state.snapshot"))
        XCTAssertFalse(settingsSource.contains("previewText"))
    }

    func testAPIKeyUsesNonLoginContentTypeAndModelIsNotACredentialField() throws {
        let settingsSource = try source("TSB/Views/SettingsView.swift")

        XCTAssertTrue(settingsSource.contains(
            "SecureField(\"API Key\", text: $model.draft.apiKey)\n                    .textContentType(.oneTimeCode)"
        ))
        XCTAssertFalse(settingsSource.contains(".textContentType(.username)"))
        XCTAssertFalse(settingsSource.contains(".textContentType(.password)"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: sourceURL(relativePath), encoding: .utf8)
    }

    private func sourceURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
    }
}

@MainActor
final class SettingsBehaviorTests: XCTestCase {
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
        let settings = try remoteSettings(historyConsent: true)
        try fixture.store.save(settings, apiKey: originalSecret)
        let failingSecretStore = KeychainSecretStore(
            service: fixture.service,
            account: fixture.account,
            keychain: fixture.keychain.reference,
            deleteItem: { _ in errSecAuthFailed }
        )
        let model = SettingsModel(store: OrganizationSettingsStore(
            defaults: fixture.defaults,
            secretStore: failingSecretStore
        ))

        model.deleteProfile()

        let blockedSettings = fixture.store.load()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(blockedSettings.endpoint, settings.endpoint)
        XCTAssertFalse(blockedSettings.isRemoteDispatchEligible)
        XCTAssertFalse(blockedSettings.canSendUserSelectedHistorySummaries)
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
        try fixture.store.save(
            try remoteSettings(historyConsent: true),
            apiKey: UUID().uuidString
        )
        let model = SettingsModel(store: fixture.store)

        model.deleteProfile()

        XCTAssertEqual(model.status, .deleted)
        XCTAssertEqual(fixture.store.load(), OrganizationSettings())
        XCTAssertFalse(model.draft.cloudConsent)
        XCTAssertFalse(model.draft.allowSelectedHistorySummaries)
        XCTAssertFalse(model.hasPersistedAPIKey)
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

    func testPolishDispatchUsesNoKeyForLoopbackAndLocalOnlyFallsBackFirst() throws {
        let endpoint = try OrganizationEndpointSettings(
            baseURL: URL(string: "http://127.0.0.1:11434/v1/chat/completions")!,
            model: "local-model"
        )
        let loopback = OrganizationSettings(endpoint: endpoint, polishEnabled: true)

        let dispatch = try AppController.makePolishDispatchSnapshot(
            loadSettings: { loopback },
            loadAPIKey: { _ in
                XCTFail("Loopback polish must not load Keychain")
                return nil
            }
        )
        XCTAssertEqual(dispatch.apiKey, "")

        var secretLoadCount = 0
        let remote = try remoteSettings()
        XCTAssertThrowsError(try AppController.makePolishDispatchSnapshot(
            localOnly: true,
            loadSettings: { remote },
            loadAPIKey: { _ in
                secretLoadCount += 1
                return "must-not-load"
            }
        )) { error in
            XCTAssertEqual(error as? TranscriptPolishDispatchError, .notEligible)
        }
        XCTAssertEqual(secretLoadCount, 0)
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
