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

enum TranscriptPolishEditKind: String, Codable, Sendable { case formatting, terminology, candidateSupported }

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
    let elapsedMilliseconds: Int?
    let errorCode: String?
    let updatedAt: Date
}

struct TranscriptDeliveryReceipt: Equatable, Codable, Sendable {
    let source: TranscriptDeliverySource
    let stopToLocalFinalMilliseconds: Int
    let stopToCopyMilliseconds: Int
}
