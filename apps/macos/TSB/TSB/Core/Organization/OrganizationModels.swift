import Foundation

enum OrganizationPersistenceState: String, Codable, Sendable {
    case pending
    case succeeded
    case failed
}

enum ProviderKind: String, Codable, Sendable {
    case local
    case remote
}

enum OrganizationNoResultReason: String, Codable, Sendable {
    case insufficientContent = "insufficient_content"
    case noReliableStructure = "no_reliable_structure"
}

enum TextSegmentValidationError: Error, Equatable {
    case emptyID
    case emptyText
}

struct TextSegment: Equatable, Codable, Sendable {
    let id: String
    let text: String

    init(id: String, text: String) throws {
        guard !id.isEmpty else { throw TextSegmentValidationError.emptyID }
        guard !text.isEmpty else { throw TextSegmentValidationError.emptyText }
        self.id = id
        self.text = text
    }
}

struct NumberedPoint: Equatable, Codable, Sendable {
    let number: Int
    let text: String
    let sourceSegmentIDs: [String]
}

struct KnownRecordLink: Equatable, Codable, Sendable {
    let recordID: SessionID
    let reason: String
    let sourceSegmentIDs: [String]
}

enum CandidateRecordLinkResolutionError: Error, Equatable {
    case unknownCandidateID(String)
}

struct CandidateRecordLink: Equatable, Codable, Sendable {
    let candidateID: String
    let reason: String
    let sourceSegmentIDs: [String]

    func resolve(using recordByCandidateID: [String: SessionID]) throws -> KnownRecordLink {
        guard let recordID = recordByCandidateID[candidateID] else {
            throw CandidateRecordLinkResolutionError.unknownCandidateID(candidateID)
        }
        return KnownRecordLink(recordID: recordID, reason: reason, sourceSegmentIDs: sourceSegmentIDs)
    }
}

struct SpeculativeConnection: Equatable, Codable, Sendable {
    let statement: String
    let whySpeculative: String
    let sourceSegmentIDs: [String]
    let relatedRecordIDs: [SessionID]
}

enum OrganizationOutputValidationError: Error, Equatable {
    case nonconsecutivePointNumbers
    case emptySourceSegmentIDs
}

struct OrganizationOutput: Equatable, Codable, Sendable {
    let noResultReason: OrganizationNoResultReason?
    let numberedPoints: [NumberedPoint]
    let knownRecordLinks: [KnownRecordLink]
    let speculativeConnections: [SpeculativeConnection]

    func validate() throws {
        for (index, point) in numberedPoints.enumerated() {
            guard point.number == index + 1 else {
                throw OrganizationOutputValidationError.nonconsecutivePointNumbers
            }
        }
        let sourceSegmentIDs = numberedPoints.map(\.sourceSegmentIDs)
            + knownRecordLinks.map(\.sourceSegmentIDs)
            + speculativeConnections.map(\.sourceSegmentIDs)
        guard sourceSegmentIDs.allSatisfy({ !$0.isEmpty }) else {
            throw OrganizationOutputValidationError.emptySourceSegmentIDs
        }
    }
}

struct OrganizationRecord: Equatable, Codable, Sendable {
    let requestID: UUID
    let inputTextSHA256: String
    let state: OrganizationPersistenceState
    let provider: String
    let model: String
    let providerKind: ProviderKind
    let selectedRecordIDs: [SessionID]
    let sentCharacterCount: Int?
    let output: OrganizationOutput?
    let errorCode: String?
    let updatedAt: Date

    init(
        requestID: UUID,
        inputTextSHA256: String,
        state: OrganizationPersistenceState,
        provider: String,
        model: String,
        providerKind: ProviderKind,
        selectedRecordIDs: [SessionID],
        sentCharacterCount: Int? = nil,
        output: OrganizationOutput?,
        errorCode: String?,
        updatedAt: Date
    ) {
        self.requestID = requestID
        self.inputTextSHA256 = inputTextSHA256
        self.state = state
        self.provider = provider
        self.model = model
        self.providerKind = providerKind
        self.selectedRecordIDs = selectedRecordIDs
        self.sentCharacterCount = sentCharacterCount
        self.output = output
        self.errorCode = errorCode
        self.updatedAt = updatedAt
    }
}
