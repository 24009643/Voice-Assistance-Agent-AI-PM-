import AppKit
import Foundation
import Security
import XCTest
@testable import TSB

final class SettingsSourceTests: XCTestCase {
    func testFullWindowContainsOnlySettingsAndAppDelegateOwnsLaunch() throws {
        let appSource = try source("TSB/App/TSBApp.swift")
        let delegateSource = try source("TSB/App/TSBAppDelegate.swift")

        XCTAssertTrue(appSource.contains("NSApplicationDelegateAdaptor"))
        XCTAssertTrue(appSource.contains("Settings {"))
        XCTAssertTrue(appSource.contains("SettingsView("))
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
            "OpenAI-compatible", "Base URL", "Model", "SecureField", "已保存", "未保存",
            "保存", "取消", "撤销云端授权", "删除配置与密钥", "出站预览",
            "当前文本", "TSB 历史摘要", "音频", "文件路径", "完整记忆库",
            "不会覆盖剪贴板", "仅本地", "另行授权",
        ] {
            XCTAssertTrue(settingsSource.contains(required), "Missing settings boundary: \(required)")
        }
        XCTAssertFalse(settingsSource.contains("state.snapshot"))
        XCTAssertFalse(settingsSource.contains("previewText"))
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
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let model = SettingsModel(store: fixture.store)
        let dummySecret = UUID().uuidString
        model.draft.baseURL = "https://example.test/v1/chat/completions"
        model.draft.model = "test-model"
        model.draft.apiKey = dummySecret

        model.save()

        XCTAssertEqual(model.status, .failed)
        XCTAssertEqual(fixture.store.load(), OrganizationSettings())
        XCTAssertThrowsError(try AppController.makeOrganizationDispatchSnapshot(
            selectedCandidateIDs: [],
            loadSettings: fixture.store.load,
            loadAPIKey: fixture.secretStore.load
        ))

        model.confirmCloudConsent()
        model.save()

        XCTAssertEqual(model.status, .saved)
        let nextSettingsSession = SettingsModel(store: fixture.store)
        XCTAssertTrue(nextSettingsSession.draft.cloudConsent)
        XCTAssertNoThrow(try AppController.makeOrganizationDispatchSnapshot(
            selectedCandidateIDs: [],
            loadSettings: fixture.store.load,
            loadAPIKey: fixture.secretStore.load
        ))
    }

    func testSelectedHistoryStillRequiresItsSeparateConsentAfterCloudConsent() throws {
        let fixture = makeFixture()
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
            loadAPIKey: fixture.secretStore.load
        ))

        model.draft.allowSelectedHistorySummaries = true
        model.save()

        XCTAssertNoThrow(try AppController.makeOrganizationDispatchSnapshot(
            selectedCandidateIDs: ["h1"],
            loadSettings: fixture.store.load,
            loadAPIKey: fixture.secretStore.load
        ))
    }

    func testBlankKeyPreservesAnExistingSecretOnSave() throws {
        let fixture = makeFixture()
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
        XCTAssertEqual(try fixture.secretStore.load(), originalSecret)
        XCTAssertTrue(model.hasPersistedAPIKey)
        XCTAssertTrue(model.draft.apiKey.isEmpty)
    }

    func testFailedKeyReplacementKeepsTheOldProfileAndSecret() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let originalSecret = UUID().uuidString
        let originalSettings = try remoteSettings(model: "old-model")
        try fixture.store.save(originalSettings, apiKey: originalSecret)
        let failingSecretStore = KeychainSecretStore(
            service: fixture.service,
            account: fixture.account,
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

        XCTAssertEqual(model.status, .failed)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(fixture.store.load(), originalSettings)
        XCTAssertEqual(try fixture.secretStore.load(), originalSecret)
    }

    func testCancelReloadsPersistedDraftWithoutAnyWrite() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let originalSecret = UUID().uuidString
        let originalSettings = try remoteSettings(model: "persisted-model", historyConsent: true)
        try fixture.store.save(originalSettings, apiKey: originalSecret)
        let writeRejectingSecretStore = KeychainSecretStore(
            service: fixture.service,
            account: fixture.account,
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
        XCTAssertEqual(try fixture.secretStore.load(), originalSecret)
    }

    func testDeleteFailureIsVisibleAndNeverClaimsDeletion() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        try fixture.store.save(try remoteSettings(), apiKey: UUID().uuidString)
        let failingSecretStore = KeychainSecretStore(
            service: fixture.service,
            account: fixture.account,
            deleteItem: { _ in errSecAuthFailed }
        )
        let model = SettingsModel(store: OrganizationSettingsStore(
            defaults: fixture.defaults,
            secretStore: failingSecretStore
        ))

        model.deleteProfile()

        XCTAssertEqual(model.status, .failed)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(fixture.store.load(), OrganizationSettings())
        XCTAssertTrue(model.hasPersistedAPIKey)
        XCTAssertNotNil(try fixture.secretStore.load())
    }

    func testDeleteRemovesProfileAndKeyBeforeClaimingSuccess() throws {
        let fixture = makeFixture()
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
        XCTAssertNil(try fixture.secretStore.load())
    }

    func testRevokeClearsBothConsentsAndDeletesTheSecret() throws {
        let fixture = makeFixture()
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
        XCTAssertNil(try fixture.secretStore.load())
        XCTAssertNotNil(fixture.store.load().endpoint)
    }

    func testLoopbackHTTPSemanticsDoNotRequireCloudConsentOrAKey() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let model = SettingsModel(store: fixture.store)
        model.draft.baseURL = "http://127.0.0.1:11434/v1/chat/completions"
        model.draft.model = "local-model"

        model.save()

        XCTAssertEqual(model.status, .saved)
        XCTAssertNoThrow(try AppController.makeOrganizationDispatchSnapshot(
            selectedCandidateIDs: [],
            loadSettings: fixture.store.load,
            loadAPIKey: fixture.secretStore.load
        ))
    }

    func testRemoteHTTPIsRejectedWithoutChangingPersistence() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let model = SettingsModel(store: fixture.store)
        model.draft.baseURL = "http://example.test/v1/chat/completions"
        model.draft.model = "test-model"
        model.draft.apiKey = UUID().uuidString
        model.confirmCloudConsent()

        model.save()

        XCTAssertEqual(model.status, .failed)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(fixture.store.load(), OrganizationSettings())
    }

    func testAppDelegateStartsAtLaunchAndStopsOnlyAtTermination() {
        let fixture = makeFixture()
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
        model: String = "test-model",
        historyConsent: Bool = false
    ) throws -> OrganizationSettings {
        OrganizationSettings(
            endpoint: try OrganizationEndpointSettings(
                baseURL: URL(string: "https://example.test/v1/chat/completions")!,
                model: model
            ),
            cloudConsentVersion: OrganizationSettings.currentCloudConsentVersion,
            allowUserSelectedHistorySummaries: historyConsent
        )
    }

    private func makeFixture() -> SettingsFixture {
        let suiteName = "SettingsBehaviorTests.\(UUID().uuidString)"
        let service = "SettingsBehaviorTests.\(UUID().uuidString)"
        let account = "api-key"
        let defaults = UserDefaults(suiteName: suiteName)!
        let secretStore = KeychainSecretStore(service: service, account: account)
        return SettingsFixture(
            suiteName: suiteName,
            service: service,
            account: account,
            defaults: defaults,
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
    let secretStore: KeychainSecretStore
    let store: OrganizationSettingsStore

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        try? secretStore.delete()
    }
}
