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
    let output: OrganizationOutput?
    let errorCode: String?
    let updatedAt: Date
}
