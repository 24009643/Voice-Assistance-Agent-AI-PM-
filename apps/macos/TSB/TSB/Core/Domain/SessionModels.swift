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
    let deliveryStatus: DeliveryStatus
}
