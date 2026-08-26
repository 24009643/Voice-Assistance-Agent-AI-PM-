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

    var credentialBindingIdentity: String { baseURL.standardized.absoluteString }

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
        guard let scheme = url.scheme?.lowercased(),
              url.host != nil,
              url.user == nil,
              url.password == nil,
              url.fragment == nil else { return false }
        let isLoopback = ["localhost", "127.0.0.1", "::1"].contains(url.host?.lowercased())
        return scheme == "https" || (scheme == "http" && isLoopback)
    }
}

struct OrganizationSettings: Equatable, Codable, Sendable {
    static let currentCloudConsentVersion = OrganizationRequestContract.consentVersion
    static let currentPolishConsentVersion = 1

    var endpoint: OrganizationEndpointSettings?
    var cloudConsentVersion: Int?
    var allowUserSelectedHistorySummaries: Bool
    var polishEnabled: Bool
    var polishConsentVersion: Int?
    var transcriptTerminology: [TranscriptTerminologyEntry]

    private enum CodingKeys: String, CodingKey {
        case endpoint, cloudConsentVersion, allowUserSelectedHistorySummaries
        case polishEnabled, polishConsentVersion, transcriptTerminology
    }

    init(
        endpoint: OrganizationEndpointSettings? = nil,
        cloudConsentVersion: Int? = nil,
        allowUserSelectedHistorySummaries: Bool = false,
        polishEnabled: Bool = false,
        polishConsentVersion: Int? = nil,
        transcriptTerminology: [TranscriptTerminologyEntry] = []
    ) {
        self.endpoint = endpoint
        self.cloudConsentVersion = cloudConsentVersion
        self.allowUserSelectedHistorySummaries = allowUserSelectedHistorySummaries
        self.polishEnabled = polishEnabled
        self.polishConsentVersion = polishConsentVersion
        self.transcriptTerminology = transcriptTerminology
    }

    var isRemoteDispatchEligible: Bool {
        endpoint?.isRemote == true && cloudConsentVersion == Self.currentCloudConsentVersion
    }

    var canSendUserSelectedHistorySummaries: Bool {
        isRemoteDispatchEligible && allowUserSelectedHistorySummaries
    }

    var isPolishDispatchEligible: Bool {
        guard polishEnabled, let endpoint else { return false }
        return endpoint.isLoopback || polishConsentVersion == Self.currentPolishConsentVersion
    }

    var requiresRemoteCredential: Bool {
        endpoint?.isRemote == true && (isRemoteDispatchEligible || isPolishDispatchEligible)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try container.decodeIfPresent(OrganizationEndpointSettings.self, forKey: .endpoint)
        cloudConsentVersion = try container.decodeIfPresent(Int.self, forKey: .cloudConsentVersion)
        allowUserSelectedHistorySummaries = try container.decodeIfPresent(Bool.self, forKey: .allowUserSelectedHistorySummaries) ?? false
        polishEnabled = try container.decodeIfPresent(Bool.self, forKey: .polishEnabled) ?? false
        polishConsentVersion = try container.decodeIfPresent(Int.self, forKey: .polishConsentVersion)
        transcriptTerminology = try container.decodeIfPresent([TranscriptTerminologyEntry].self, forKey: .transcriptTerminology) ?? []
    }
}
