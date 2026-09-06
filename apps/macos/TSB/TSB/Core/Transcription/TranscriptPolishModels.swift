import CryptoKit
import Foundation

enum TranscriptPolishState: String, Codable, Sendable {
    case notRequested, accepted, reviewRequired, timedOut, rejected, failed, cancelled
}

enum TranscriptDeliverySource: String, Codable, Sendable { case local, polished }

struct TranscriptCandidate: Equatable, Sendable {
    enum ID: String, Codable, Sendable { case offline, streaming }
    let id: ID
    let text: String
    let textSHA256: String

    init(id: ID, text: String) {
        self.id = id
        self.text = text
        textSHA256 = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum TranscriptPolishEditKind: String, Codable, Sendable {
    case formatting
    case terminology
    case candidateSupported = "candidate_supported"
}

struct TranscriptPolishEdit: Equatable, Codable, Sendable {
    let kind: TranscriptPolishEditKind
    let startUTF16: Int
    let lengthUTF16: Int
    let original: String
    let replacement: String
    let reason: String
}

enum TranscriptPolishOutcome: Equatable, Sendable {
    case accepted(baseCandidateID: TranscriptCandidate.ID, text: String, edits: [TranscriptPolishEdit])
    case reviewRequired(baseCandidateID: TranscriptCandidate.ID, text: String, edits: [TranscriptPolishEdit])
}

struct TranscriptPolishRecord: Equatable, Codable, Sendable {
    let requestID: UUID
    let state: TranscriptPolishState
    let baseCandidateID: TranscriptCandidate.ID?
    let polishedText: String?
    let reviewCandidateText: String?
    let edits: [TranscriptPolishEdit]
    let provider: String?
    let model: String?
    let providerKind: ProviderKind?
    let sentCharacterCount: Int?
    let selectedHistoryRecordCount: Int
    let elapsedMilliseconds: Int?
    let errorCode: String?
    let updatedAt: Date

    init(
        requestID: UUID,
        state: TranscriptPolishState,
        baseCandidateID: TranscriptCandidate.ID?,
        polishedText: String?,
        reviewCandidateText: String?,
        edits: [TranscriptPolishEdit],
        provider: String?,
        model: String?,
        providerKind: ProviderKind?,
        sentCharacterCount: Int?,
        selectedHistoryRecordCount: Int = 0,
        elapsedMilliseconds: Int?,
        errorCode: String?,
        updatedAt: Date
    ) {
        self.requestID = requestID
        self.state = state
        self.baseCandidateID = baseCandidateID
        self.polishedText = polishedText
        self.reviewCandidateText = reviewCandidateText
        self.edits = edits
        self.provider = provider
        self.model = model
        self.providerKind = providerKind
        self.sentCharacterCount = sentCharacterCount
        self.selectedHistoryRecordCount = selectedHistoryRecordCount
        self.elapsedMilliseconds = elapsedMilliseconds
        self.errorCode = errorCode
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case requestID, state, baseCandidateID, polishedText, reviewCandidateText, edits
        case provider, model, providerKind, sentCharacterCount, selectedHistoryRecordCount
        case elapsedMilliseconds, errorCode, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decode(UUID.self, forKey: .requestID)
        state = try container.decode(TranscriptPolishState.self, forKey: .state)
        baseCandidateID = try container.decodeIfPresent(TranscriptCandidate.ID.self, forKey: .baseCandidateID)
        polishedText = try container.decodeIfPresent(String.self, forKey: .polishedText)
        reviewCandidateText = try container.decodeIfPresent(String.self, forKey: .reviewCandidateText)
        edits = try container.decode([TranscriptPolishEdit].self, forKey: .edits)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        providerKind = try container.decodeIfPresent(ProviderKind.self, forKey: .providerKind)
        sentCharacterCount = try container.decodeIfPresent(Int.self, forKey: .sentCharacterCount)
        selectedHistoryRecordCount = try container.decodeIfPresent(Int.self, forKey: .selectedHistoryRecordCount) ?? 0
        elapsedMilliseconds = try container.decodeIfPresent(Int.self, forKey: .elapsedMilliseconds)
        errorCode = try container.decodeIfPresent(String.self, forKey: .errorCode)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct TranscriptDeliveryReceipt: Equatable, Codable, Sendable {
    let source: TranscriptDeliverySource
    let stopToLocalFinalMilliseconds: Int
    let stopToCopyMilliseconds: Int
}
