import Foundation

struct SecondaryProcessingSnapshot: Equatable, Sendable, Identifiable {
    let id: SessionID
    let status: SessionStatus
    let previewText: String
    let message: String
}

struct AppSnapshot: Equatable, Sendable {
    let status: SessionStatus
    let elapsedMilliseconds: Int
    let previewText: String
    let message: String?
    let secondaryProcessing: [SecondaryProcessingSnapshot]
    let canStartRecording: Bool

    init(
        status: SessionStatus,
        elapsedMilliseconds: Int,
        previewText: String,
        message: String?,
        secondaryProcessing: [SecondaryProcessingSnapshot] = [],
        canStartRecording: Bool = true
    ) {
        self.status = status
        self.elapsedMilliseconds = elapsedMilliseconds
        self.previewText = previewText
        self.message = message
        self.secondaryProcessing = secondaryProcessing
        self.canStartRecording = canStartRecording
    }
}
