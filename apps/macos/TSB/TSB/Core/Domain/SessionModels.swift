import Foundation

struct SessionID: Hashable, Codable, Sendable {
    let rawValue: UUID
}

struct SessionOrdinal: Hashable, Comparable, Codable, Sendable {
    let rawValue: UInt64

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum SessionStatus: String, Codable, Sendable {
    case idle
    case recording
    case transcribing
    case saving
    case delivered
    case failed
    case cancelled
}

enum DeliveryStatus: String, Codable, Sendable {
    case pending
    case copied
    case failed
}

enum TranscriptOutcome: String, Codable, Sendable {
    case success
    case recordingFailed
    case transcriptionFailed
    case noSpeech
}

enum TranscriptFinalSource: String, Codable, Sendable {
    case senseVoice
    case streamingFallback
}

enum TranscriptReviewState: String, Codable, Sendable {
    case unreviewed
    case reviewed
}

enum TranscriptIntendedUse: String, Codable, Sendable {
    case localEvaluation
}

struct EditOperation: Equatable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case trim
        case whitespace
        case repeatedPunctuation
    }

    let kind: Kind
    let startUTF16: Int
    let lengthUTF16: Int
    let original: String
    let replacement: String
}

struct CleanResult: Equatable, Codable, Sendable {
    let text: String
    let edits: [EditOperation]
}

struct TranscriptRecord: Equatable, Codable, Sendable {
    let id: SessionID
    let ordinal: SessionOrdinal
    let createdAt: Date
    let durationMilliseconds: Int
    let detectedLanguages: [String]
    let originalText: String
    let localCleanedText: String
    let edits: [EditOperation]
    var deliveryStatus: DeliveryStatus
    let outcome: TranscriptOutcome
    let error: String?
    let finalSource: TranscriptFinalSource?
    let languageSlice: String?
    let localEvaluationConsent: Bool?
    let reviewState: TranscriptReviewState
    let intendedUse: TranscriptIntendedUse

    private enum CodingKeys: String, CodingKey {
        case id
        case ordinal
        case createdAt
        case durationMilliseconds
        case detectedLanguages
        case originalText
        case localCleanedText
        case edits
        case deliveryStatus
        case outcome
        case error
        case finalSource
        case languageSlice
        case localEvaluationConsent
        case reviewState
        case intendedUse
    }

    init(
        id: SessionID,
        ordinal: SessionOrdinal,
        createdAt: Date,
        durationMilliseconds: Int,
        detectedLanguages: [String],
        originalText: String,
        localCleanedText: String,
        edits: [EditOperation],
        deliveryStatus: DeliveryStatus,
        outcome: TranscriptOutcome = .success,
        error: String? = nil,
        finalSource: TranscriptFinalSource? = .senseVoice,
        languageSlice: String? = nil,
        localEvaluationConsent: Bool? = nil,
        reviewState: TranscriptReviewState = .unreviewed,
        intendedUse: TranscriptIntendedUse = .localEvaluation
    ) {
        self.id = id
        self.ordinal = ordinal
        self.createdAt = createdAt
        self.durationMilliseconds = durationMilliseconds
        self.detectedLanguages = detectedLanguages
        self.originalText = originalText
        self.localCleanedText = localCleanedText
        self.edits = edits
        self.deliveryStatus = deliveryStatus
        self.outcome = outcome
        self.error = error
        self.finalSource = finalSource
        self.languageSlice = languageSlice
        self.localEvaluationConsent = localEvaluationConsent
        self.reviewState = reviewState
        self.intendedUse = intendedUse
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SessionID.self, forKey: .id)
        ordinal = try container.decode(SessionOrdinal.self, forKey: .ordinal)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        durationMilliseconds = try container.decode(Int.self, forKey: .durationMilliseconds)
        detectedLanguages = try container.decode([String].self, forKey: .detectedLanguages)
        originalText = try container.decode(String.self, forKey: .originalText)
        localCleanedText = try container.decode(String.self, forKey: .localCleanedText)
        edits = try container.decode([EditOperation].self, forKey: .edits)
        deliveryStatus = try container.decode(DeliveryStatus.self, forKey: .deliveryStatus)
        outcome = try container.decodeIfPresent(TranscriptOutcome.self, forKey: .outcome) ?? .success
        error = try container.decodeIfPresent(String.self, forKey: .error)
        finalSource = try container.decodeIfPresent(TranscriptFinalSource.self, forKey: .finalSource)
        languageSlice = try container.decodeIfPresent(String.self, forKey: .languageSlice)
        localEvaluationConsent = try container.decodeIfPresent(Bool.self, forKey: .localEvaluationConsent)
        reviewState = try container.decodeIfPresent(TranscriptReviewState.self, forKey: .reviewState) ?? .unreviewed
        intendedUse = try container.decodeIfPresent(TranscriptIntendedUse.self, forKey: .intendedUse) ?? .localEvaluation
    }
}
