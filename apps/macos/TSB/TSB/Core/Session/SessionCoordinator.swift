import Foundation

@MainActor
final class SessionCoordinator {
    struct Dependencies {
        let startRecording: @MainActor (SessionID, @escaping @Sendable (RecordedAudio) -> Void) throws -> Void
        let stopRecording: @MainActor () -> Void
        let cancelRecording: @MainActor () -> Void
        let transcribe: @MainActor (URL) async throws -> TranscriptionResult
        let clean: @MainActor (String) throws -> CleanResult
        let save: @MainActor (TranscriptRecord) throws -> Void
        let updateDeliveryStatus: @MainActor (SessionID, DeliveryStatus) throws -> Void
        let copy: @MainActor (String) -> Bool
        let removeAudio: @MainActor (URL) throws -> Void
    }

    private struct ActiveSession {
        let id: SessionID
        let ordinal: SessionOrdinal
        let createdAt: Date
    }

    private let dependencies: Dependencies
    private let onSnapshot: (AppSnapshot) -> Void
    private var activeSession: ActiveSession?
    private var stopRequested = false
    private var nextOrdinal: UInt64 = 1
    private var deliveredSessionIDs = Set<SessionID>()
    private var processingTask: Task<Void, Never>?

    private(set) var snapshot = AppSnapshot(status: .idle, elapsedMilliseconds: 0, previewText: "", message: nil) {
        didSet { onSnapshot(snapshot) }
    }

    init(dependencies: Dependencies, onSnapshot: @escaping (AppSnapshot) -> Void) {
        self.dependencies = dependencies
        self.onSnapshot = onSnapshot
    }

    func handle(_ intent: UserIntent) async {
        switch intent {
        case .toggleRecording:
            if activeSession == nil {
                startRecording()
            } else if snapshot.status == .recording, !stopRequested {
                stopRequested = true
                dependencies.stopRecording()
            }
        case .cancelRecording:
            cancelRecording()
        }
    }

    private func startRecording() {
        let session = ActiveSession(
            id: SessionID(rawValue: UUID()),
            ordinal: SessionOrdinal(rawValue: nextOrdinal),
            createdAt: Date()
        )
        nextOrdinal += 1
        activeSession = session
        stopRequested = false

        do {
            try dependencies.startRecording(session.id) { [weak self] audio in
                Task { @MainActor [weak self] in
                    self?.receiveFinishedAudio(audio, for: session.id)
                }
            }
            snapshot = AppSnapshot(status: .recording, elapsedMilliseconds: 0, previewText: "", message: "Recording")
        } catch {
            activeSession = nil
            snapshot = AppSnapshot(status: .failed, elapsedMilliseconds: 0, previewText: "", message: "Could not start recording.")
        }
    }

    private func receiveFinishedAudio(_ audio: RecordedAudio, for sessionID: SessionID) {
        guard activeSession?.id == sessionID, processingTask == nil else { return }

        snapshot = AppSnapshot(status: .transcribing, elapsedMilliseconds: audio.durationMilliseconds, previewText: "", message: "Transcribing")
        processingTask = Task { @MainActor [weak self] in
            await self?.process(audio, for: sessionID)
        }
    }

    private func process(_ audio: RecordedAudio, for sessionID: SessionID) async {
        defer { processingTask = nil }
        guard let session = activeSession, session.id == sessionID else { return }

        let transcription: TranscriptionResult
        do {
            transcription = try await dependencies.transcribe(audio.url)
        } catch {
            snapshot = AppSnapshot(status: .failed, elapsedMilliseconds: audio.durationMilliseconds, previewText: "", message: "Transcription failed.")
            activeSession = nil
            return
        }

        guard !Task.isCancelled, activeSession?.id == sessionID else { return }

        let cleaned: CleanResult
        do {
            cleaned = try dependencies.clean(transcription.text)
        } catch {
            cleaned = CleanResult(text: transcription.text, edits: [])
        }

        guard !cleaned.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            try? dependencies.removeAudio(audio.url)
            activeSession = nil
            snapshot = AppSnapshot(status: .cancelled, elapsedMilliseconds: audio.durationMilliseconds, previewText: "", message: "No speech detected.")
            return
        }

        let record = TranscriptRecord(
            id: session.id,
            ordinal: session.ordinal,
            createdAt: session.createdAt,
            durationMilliseconds: audio.durationMilliseconds,
            detectedLanguages: transcription.detectedLanguage.map { [$0] } ?? [],
            originalText: transcription.text,
            localCleanedText: cleaned.text,
            edits: cleaned.edits,
            deliveryStatus: .pending
        )
        snapshot = AppSnapshot(status: .saving, elapsedMilliseconds: audio.durationMilliseconds, previewText: cleaned.text, message: "Saving")

        do {
            try dependencies.save(record)
        } catch {
            activeSession = nil
            snapshot = AppSnapshot(status: .failed, elapsedMilliseconds: audio.durationMilliseconds, previewText: cleaned.text, message: "Could not save transcript.")
            return
        }

        try? dependencies.removeAudio(audio.url)
        activeSession = nil

        guard deliveredSessionIDs.insert(session.id).inserted else { return }
        let didCopy = dependencies.copy(cleaned.text)
        let deliveryStatus: DeliveryStatus = didCopy ? .copied : .failed

        do {
            try dependencies.updateDeliveryStatus(session.id, deliveryStatus)
            snapshot = AppSnapshot(
                status: didCopy ? .delivered : .failed,
                elapsedMilliseconds: audio.durationMilliseconds,
                previewText: cleaned.text,
                message: didCopy ? "Copied to clipboard." : "Could not copy to clipboard."
            )
        } catch {
            snapshot = AppSnapshot(status: .failed, elapsedMilliseconds: audio.durationMilliseconds, previewText: cleaned.text, message: "Could not update delivery status.")
        }
    }

    private func cancelRecording() {
        guard activeSession != nil else { return }

        processingTask?.cancel()
        processingTask = nil
        dependencies.cancelRecording()
        activeSession = nil
        stopRequested = false
        snapshot = AppSnapshot(status: .cancelled, elapsedMilliseconds: 0, previewText: "", message: "Recording cancelled.")
    }
}
