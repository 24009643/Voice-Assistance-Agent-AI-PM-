import Foundation

enum OrganizationPhase: Equatable, Sendable {
    case notRequested
    case authorizationRequired
    case localOnly
    case queued
    case organizing
    case organized(OrganizationRecord)
    case failed(String)
}

enum OrganizationIntent: Equatable, Sendable {
    case setLocalOnly(sessionID: SessionID, enabled: Bool)
    case cancel(sessionID: SessionID, requestID: UUID)
    case retry(sessionID: SessionID, requestID: UUID)
    case enrichLinks(sessionID: SessionID, selectedRecordIDs: Set<SessionID>)
}

struct SuggestedRecordSnapshot: Equatable, Sendable, Identifiable {
    let id: SessionID
    let summary: String
}

struct SecondaryProcessingSnapshot: Equatable, Sendable, Identifiable {
    let id: SessionID
    let status: SessionStatus
    let previewText: String
    let originalText: String
    let message: String
    let organizationPhase: OrganizationPhase
    let organizationRequestID: UUID?
    let suggestedRecords: [SuggestedRecordSnapshot]

    init(
        id: SessionID,
        status: SessionStatus,
        previewText: String,
        originalText: String = "",
        message: String,
        organizationPhase: OrganizationPhase = .notRequested,
        organizationRequestID: UUID? = nil,
        suggestedRecords: [SuggestedRecordSnapshot] = []
    ) {
        self.id = id
        self.status = status
        self.previewText = previewText
        self.originalText = originalText
        self.message = message
        self.organizationPhase = organizationPhase
        self.organizationRequestID = organizationRequestID
        self.suggestedRecords = suggestedRecords
    }
}

struct AppSnapshot: Equatable, Sendable {
    let sessionID: SessionID?
    let status: SessionStatus
    let elapsedMilliseconds: Int
    let previewText: String
    let originalText: String
    let message: String?
    let audioLevel: Float
    let organizationPhase: OrganizationPhase
    let organizationRequestID: UUID?
    let suggestedRecords: [SuggestedRecordSnapshot]
    let secondaryProcessing: [SecondaryProcessingSnapshot]
    let canStartRecording: Bool

    init(
        sessionID: SessionID? = nil,
        status: SessionStatus,
        elapsedMilliseconds: Int,
        previewText: String,
        originalText: String = "",
        message: String?,
        audioLevel: Float = 0,
        organizationPhase: OrganizationPhase = .notRequested,
        organizationRequestID: UUID? = nil,
        suggestedRecords: [SuggestedRecordSnapshot] = [],
        secondaryProcessing: [SecondaryProcessingSnapshot] = [],
        canStartRecording: Bool = true
    ) {
        self.sessionID = sessionID
        self.status = status
        self.elapsedMilliseconds = elapsedMilliseconds
        self.previewText = previewText
        self.originalText = originalText
        self.message = message
        self.audioLevel = audioLevel
        self.organizationPhase = organizationPhase
        self.organizationRequestID = organizationRequestID
        self.suggestedRecords = suggestedRecords
        self.secondaryProcessing = secondaryProcessing
        self.canStartRecording = canStartRecording
    }
}
