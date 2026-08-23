import Foundation

enum OrganizationEndpointSettingsError: Error, Equatable {
    case insecureEndpoint
}

struct OrganizationEndpointSettings: Equatable, Codable, Sendable {
    let baseURL: URL
    let model: String

    private enum CodingKeys: String, CodingKey {
        case baseURL
        case model
    }

    init(baseURL: URL, model: String) throws {
        guard Self.isAllowed(baseURL) else { throw OrganizationEndpointSettingsError.insecureEndpoint }
        self.baseURL = baseURL
        self.model = model
    }

    var isLoopback: Bool {
        ["localhost", "127.0.0.1", "::1"].contains(baseURL.host?.lowercased())
    }

    var isRemote: Bool { !isLoopback }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(model, forKey: .model)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            baseURL: container.decode(URL.self, forKey: .baseURL),
            model: container.decode(String.self, forKey: .model)
        )
    }

    private static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), url.host != nil else { return false }
        let isLoopback = ["localhost", "127.0.0.1", "::1"].contains(url.host?.lowercased())
        return scheme == "https" || (scheme == "http" && isLoopback)
    }
}

struct OrganizationSettings: Equatable, Codable, Sendable {
    static let currentCloudConsentVersion = OrganizationRequestContract.consentVersion

    var endpoint: OrganizationEndpointSettings?
    var cloudConsentVersion: Int?
    var allowUserSelectedHistorySummaries: Bool

    init(
        endpoint: OrganizationEndpointSettings? = nil,
        cloudConsentVersion: Int? = nil,
        allowUserSelectedHistorySummaries: Bool = false
    ) {
        self.endpoint = endpoint
        self.cloudConsentVersion = cloudConsentVersion
        self.allowUserSelectedHistorySummaries = allowUserSelectedHistorySummaries
    }

    var isRemoteDispatchEligible: Bool {
        endpoint?.isRemote == true && cloudConsentVersion == Self.currentCloudConsentVersion
    }

    var canSendUserSelectedHistorySummaries: Bool {
        isRemoteDispatchEligible && allowUserSelectedHistorySummaries
    }
}
