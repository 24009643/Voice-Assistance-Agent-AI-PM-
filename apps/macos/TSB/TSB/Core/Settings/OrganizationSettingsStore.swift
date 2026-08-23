import Foundation

final class OrganizationSettingsStore {
    static let storageKey = "organization-settings.v1"

    private let defaults: UserDefaults
    private let secretStore: KeychainSecretStore

    init(defaults: UserDefaults = .standard, secretStore: KeychainSecretStore = KeychainSecretStore()) {
        self.defaults = defaults
        self.secretStore = secretStore
    }

    func load() -> OrganizationSettings {
        guard let data = defaults.data(forKey: Self.storageKey),
              let settings = try? JSONDecoder().decode(OrganizationSettings.self, from: data) else {
            return OrganizationSettings()
        }
        return settings
    }

    func hasAPIKey() throws -> Bool {
        try secretStore.hasSecret()
    }

    func save(_ settings: OrganizationSettings, apiKey: String? = nil) throws {
        let data = try JSONEncoder().encode(settings)
        if settings.isRemoteDispatchEligible, let apiKey {
            try secretStore.save(apiKey)
        } else if !settings.isRemoteDispatchEligible {
            try secretStore.delete()
        }
        defaults.set(data, forKey: Self.storageKey)
    }

    func revokeCloudConsent() throws {
        var settings = load()
        settings.cloudConsentVersion = nil
        settings.allowUserSelectedHistorySummaries = false
        defaults.set(try JSONEncoder().encode(settings), forKey: Self.storageKey)
        try secretStore.delete()
    }

    func delete() throws {
        defaults.removeObject(forKey: Self.storageKey)
        try secretStore.delete()
    }
}
