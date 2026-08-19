import Foundation

@MainActor
final class SessionCoordinator {
    struct Dependencies {
        let startRecording: @MainActor (
            SessionID,
            @escaping @Sendable (RecordedAudio) -> Void,
            @escaping @Sendable (RecordedAudio) -> Void
        ) throws -> Void
        let stopRecording: @MainActor () -> Void
        let cancelRecording: @MainActor (SessionID) -> Void
        let transcribe: @MainActor (URL) async throws -> TranscriptionResult
        let clean: @MainActor (String) throws -> CleanResult
        let save: @MainActor (TranscriptRecord) throws -> Void
        let updateDeliveryStatus: @MainActor (SessionID, DeliveryStatus) throws -> Void
        let copy: @MainActor (String) -> Bool
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
    private var activeDeliverySucceeded: Bool?
    private var processingTask: Task<Void, Never>?
    private var processingSessionID: SessionID?

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
        activeDeliverySucceeded = nil

        do {
            try dependencies.startRecording(
                session.id,
                { [weak self] audio in
                    Task { @MainActor [weak self] in
                        self?.receiveFinishedAudio(audio, for: session.id)
                    }
                },
                { [weak self] audio in
                    Task { @MainActor [weak self] in
                        self?.receiveRecordingFailure(audio, for: session.id)
                    }
                }
            )
            snapshot = AppSnapshot(status: .recording, elapsedMilliseconds: 0, previewText: "", message: "Recording")
        } catch {
            activeSession = nil
            snapshot = AppSnapshot(status: .failed, elapsedMilliseconds: 0, previewText: "", message: "Could not start recording.")
        }
    }

    private func receiveFinishedAudio(_ audio: RecordedAudio, for sessionID: SessionID) {
        guard activeSession?.id == sessionID, processingSessionID == nil else { return }

        snapshot = AppSnapshot(status: .transcribing, elapsedMilliseconds: audio.durationMilliseconds, previewText: "", message: "Transcribing")
        processingSessionID = sessionID
        processingTask = Task { @MainActor [weak self] in
            await self?.process(audio, for: sessionID)
        }
    }

    private func receiveRecordingFailure(_ audio: RecordedAudio, for sessionID: SessionID) {
        guard let session = activeSession, session.id == sessionID, processingSessionID == nil else { return }
        let record = TranscriptRecord(
            id: session.id,
            ordinal: session.ordinal,
            createdAt: session.createdAt,
            durationMilliseconds: audio.durationMilliseconds,
            detectedLanguages: [],
            originalText: "",
            localCleanedText: "",
            edits: [],
            deliveryStatus: .pending,
            outcome: .recordingFailed,
            error: "recording_failed",
            finalSource: nil
        )
        guard save(record, for: sessionID, durationMilliseconds: audio.durationMilliseconds, previewText: "") else { return }
        finish(
            sessionID,
            with: .failed,
            durationMilliseconds: audio.durationMilliseconds,
            previewText: "",
            message: "Recording failed."
        )
    }

    private func process(_ audio: RecordedAudio, for sessionID: SessionID) async {
        defer {
            if processingSessionID == sessionID {
                processingTask = nil
                processingSessionID = nil
            }
        }
        guard let session = activeSession, session.id == sessionID else { return }

        let transcription: TranscriptionResult
        do {
            transcription = try await dependencies.transcribe(audio.url)
        } catch {
            guard owns(sessionID) else { return }
            let record = TranscriptRecord(
                id: session.id,
                ordinal: session.ordinal,
                createdAt: session.createdAt,
                durationMilliseconds: audio.durationMilliseconds,
                detectedLanguages: [],
                originalText: "",
                localCleanedText: "",
                edits: [],
                deliveryStatus: .pending,
                outcome: .transcriptionFailed,
                error: "transcription_failed",
                finalSource: nil
            )
            guard save(record, for: sessionID, durationMilliseconds: audio.durationMilliseconds, previewText: "") else { return }
            finish(sessionID, with: .failed, durationMilliseconds: audio.durationMilliseconds, previewText: "", message: "Transcription failed.")
            return
        }

        guard owns(sessionID) else { return }

        let cleaned: CleanResult
        do {
            cleaned = try dependencies.clean(transcription.text)
        } catch {
            cleaned = CleanResult(text: transcription.text, edits: [])
        }

        guard !cleaned.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let record = TranscriptRecord(
                id: session.id,
                ordinal: session.ordinal,
                createdAt: session.createdAt,
                durationMilliseconds: audio.durationMilliseconds,
                detectedLanguages: transcription.detectedLanguage.map { [$0] } ?? [],
                originalText: transcription.text,
                localCleanedText: cleaned.text,
                edits: cleaned.edits,
                deliveryStatus: .pending,
                outcome: .noSpeech
            )
            guard save(record, for: sessionID, durationMilliseconds: audio.durationMilliseconds, previewText: cleaned.text) else { return }
            finish(sessionID, with: .cancelled, durationMilliseconds: audio.durationMilliseconds, previewText: "", message: "No speech detected.")
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
            finish(sessionID, with: .failed, durationMilliseconds: audio.durationMilliseconds, previewText: cleaned.text, message: "Could not save transcript.")
            return
        }

        guard owns(sessionID), activeDeliverySucceeded == nil else { return }

        let didCopy = dependencies.copy(cleaned.text)
        activeDeliverySucceeded = didCopy

        do {
            try dependencies.updateDeliveryStatus(session.id, didCopy ? .copied : .failed)
            finish(
                sessionID,
                with: didCopy ? .delivered : .failed,
                durationMilliseconds: audio.durationMilliseconds,
                previewText: cleaned.text,
                message: didCopy ? "已复制 · 按 ⌘V 粘贴" : "Could not copy to clipboard."
            )
        } catch {
            finish(
                sessionID,
                with: didCopy ? .delivered : .failed,
                durationMilliseconds: audio.durationMilliseconds,
                previewText: cleaned.text,
                message: didCopy ? "已复制，但未能记录复制状态" : "Could not update delivery status."
            )
        }
    }

    private func cancelRecording() {
        guard let session = activeSession else { return }

        processingTask?.cancel()
        processingTask = nil
        processingSessionID = nil
        dependencies.cancelRecording(session.id)
        activeSession = nil
        stopRequested = false
        activeDeliverySucceeded = nil
        snapshot = AppSnapshot(status: .cancelled, elapsedMilliseconds: 0, previewText: "", message: "Recording cancelled.")
    }

    private func owns(_ sessionID: SessionID) -> Bool {
        !Task.isCancelled && activeSession?.id == sessionID
    }

    private func save(
        _ record: TranscriptRecord,
        for sessionID: SessionID,
        durationMilliseconds: Int,
        previewText: String
    ) -> Bool {
        snapshot = AppSnapshot(status: .saving, elapsedMilliseconds: durationMilliseconds, previewText: previewText, message: "Saving")
        do {
            try dependencies.save(record)
            return owns(sessionID)
        } catch {
            finish(sessionID, with: .failed, durationMilliseconds: durationMilliseconds, previewText: previewText, message: "Could not save transcript.")
            return false
        }
    }

    private func finish(
        _ sessionID: SessionID,
        with status: SessionStatus,
        durationMilliseconds: Int,
        previewText: String,
        message: String
    ) {
        guard activeSession?.id == sessionID else { return }
        activeSession = nil
        stopRequested = false
        snapshot = AppSnapshot(status: status, elapsedMilliseconds: durationMilliseconds, previewText: previewText, message: message)
    }
}
