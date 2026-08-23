import CryptoKit
import Foundation

enum OrganizationValidatorError: Error, Equatable {
    case invalidResponseShape
    case unknownResponseField(String)
    case wrongSchemaVersion
    case wrongRequestID
    case wrongInputHash
    case nonconsecutivePointNumbers
    case unknownSegmentID(String)
    case emptySourceSegmentIDs
    case unknownCandidateID(String)
    case missingNoResultReason
    case unexpectedNoResultReason
}

struct OrganizationResponseDTO: Decodable, Sendable {
    let schemaVersion: String
    let requestID: UUID
    let sourceTextHash: String
    let noResultReason: OrganizationNoResultReason?
    let numberedPoints: [NumberedPointDTO]
    let knownRecordLinks: [CandidateRecordLinkDTO]
    let speculativeConnections: [SpeculativeConnectionDTO]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case sourceTextHash = "source_text_hash"
        case noResultReason = "no_result_reason"
        case numberedPoints = "numbered_points"
        case knownRecordLinks = "known_record_links"
        case speculativeConnections = "speculative_connections"
    }

    static func decodeStrictly(from data: Data) throws -> Self {
        let object = try JSONSerialization.jsonObject(with: data)
        let topLevel = try exactObject(object, keys: [
            "schema_version", "request_id", "source_text_hash", "no_result_reason",
            "numbered_points", "known_record_links", "speculative_connections"
        ])
        try validateObjects(topLevel["numbered_points"], keys: ["number", "text", "source_segment_ids"])
        try validateObjects(topLevel["known_record_links"], keys: ["candidate_id", "reason", "source_segment_ids"])
        try validateObjects(topLevel["speculative_connections"], keys: [
            "statement", "why_speculative", "source_segment_ids", "candidate_ids"
        ])
        return try JSONDecoder().decode(Self.self, from: data)
    }

    private static func validateObjects(_ value: Any?, keys: Set<String>) throws {
        guard let objects = value as? [Any] else { throw OrganizationValidatorError.invalidResponseShape }
        for object in objects { _ = try exactObject(object, keys: keys) }
    }

    private static func exactObject(_ value: Any, keys: Set<String>) throws -> [String: Any] {
        guard let object = value as? [String: Any] else {
            throw OrganizationValidatorError.invalidResponseShape
        }
        let actual = Set(object.keys)
        if let unknown = actual.subtracting(keys).sorted().first {
            throw OrganizationValidatorError.unknownResponseField(unknown)
        }
        guard actual == keys else { throw OrganizationValidatorError.invalidResponseShape }
        return object
    }
}

struct NumberedPointDTO: Decodable, Sendable {
    let number: Int
    let text: String
    let sourceSegmentIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case number
        case text
        case sourceSegmentIDs = "source_segment_ids"
    }
}

struct CandidateRecordLinkDTO: Decodable, Sendable {
    let candidateID: String
    let reason: String
    let sourceSegmentIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case candidateID = "candidate_id"
        case reason
        case sourceSegmentIDs = "source_segment_ids"
    }
}

struct SpeculativeConnectionDTO: Decodable, Sendable {
    let statement: String
    let whySpeculative: String
    let sourceSegmentIDs: [String]
    let candidateIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case statement
        case whySpeculative = "why_speculative"
        case sourceSegmentIDs = "source_segment_ids"
        case candidateIDs = "candidate_ids"
    }
}

struct OrganizationValidator {
    private let requestID: UUID
    private let inputTextSHA256: String
    private let currentSegmentByID: [String: TextSegment]
    private let recordByCandidateID: [String: SessionID]

    init(
        requestID: UUID,
        inputTextSHA256: String,
        currentSegmentByID: [String: TextSegment],
        recordByCandidateID: [String: SessionID]
    ) {
        self.requestID = requestID
        self.inputTextSHA256 = inputTextSHA256
        self.currentSegmentByID = currentSegmentByID
        self.recordByCandidateID = recordByCandidateID
    }

    func validate(_ response: OrganizationResponseDTO) throws -> OrganizationOutput {
        guard response.schemaVersion == "tsb.organization.output.v1" else {
            throw OrganizationValidatorError.wrongSchemaVersion
        }
        guard response.requestID == requestID else {
            throw OrganizationValidatorError.wrongRequestID
        }
        guard response.sourceTextHash == inputTextSHA256 else {
            throw OrganizationValidatorError.wrongInputHash
        }
        guard response.numberedPoints.enumerated().allSatisfy({ $0.element.number == $0.offset + 1 }) else {
            throw OrganizationValidatorError.nonconsecutivePointNumbers
        }

        let sourceIDGroups = response.numberedPoints.map(\.sourceSegmentIDs)
            + response.knownRecordLinks.map(\.sourceSegmentIDs)
            + response.speculativeConnections.map(\.sourceSegmentIDs)
        for sourceIDs in sourceIDGroups {
            guard !sourceIDs.isEmpty else { throw OrganizationValidatorError.emptySourceSegmentIDs }
            for sourceID in sourceIDs where currentSegmentByID[sourceID] == nil {
                throw OrganizationValidatorError.unknownSegmentID(sourceID)
            }
        }

        for candidateID in response.knownRecordLinks.map(\.candidateID)
            + response.speculativeConnections.flatMap(\.candidateIDs) {
            guard recordByCandidateID[candidateID] != nil else {
                throw OrganizationValidatorError.unknownCandidateID(candidateID)
            }
        }

        let isEmpty = response.numberedPoints.isEmpty
            && response.knownRecordLinks.isEmpty
            && response.speculativeConnections.isEmpty
        if isEmpty && response.noResultReason == nil {
            throw OrganizationValidatorError.missingNoResultReason
        }
        if !isEmpty && response.noResultReason != nil {
            throw OrganizationValidatorError.unexpectedNoResultReason
        }

        return OrganizationOutput(
            noResultReason: response.noResultReason,
            numberedPoints: response.numberedPoints.map {
                NumberedPoint(number: $0.number, text: $0.text, sourceSegmentIDs: $0.sourceSegmentIDs)
            },
            knownRecordLinks: try response.knownRecordLinks.map {
                try CandidateRecordLink(
                    candidateID: $0.candidateID,
                    reason: $0.reason,
                    sourceSegmentIDs: $0.sourceSegmentIDs
                ).resolve(using: recordByCandidateID)
            },
            speculativeConnections: response.speculativeConnections.map { connection in
                SpeculativeConnection(
                    statement: connection.statement,
                    whySpeculative: connection.whySpeculative,
                    sourceSegmentIDs: connection.sourceSegmentIDs,
                    relatedRecordIDs: connection.candidateIDs.compactMap { recordByCandidateID[$0] }
                )
            }
        )
    }

    static func inputTextSHA256(for segments: [TextSegment]) -> String {
        SHA256.hash(data: Data(segments.map(\.text).joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
