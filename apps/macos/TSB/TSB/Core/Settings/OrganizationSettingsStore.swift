import Foundation

enum OrganizationSettingsStoreError: Error, Equatable {
    case missingBoundSecret
}

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

    func hasAPIKey(for endpoint: OrganizationEndpointSettings) throws -> Bool {
        try secretStore.hasSecret(for: endpoint)
    }

    func save(_ settings: OrganizationSettings, apiKey: String? = nil) throws {
        let data = try JSONEncoder().encode(settings)
        if settings.isRemoteDispatchEligible, let endpoint = settings.endpoint {
            if let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try secretStore.save(apiKey, for: endpoint)
            } else if try !secretStore.hasSecret(for: endpoint) {
                throw OrganizationSettingsStoreError.missingBoundSecret
            }
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
