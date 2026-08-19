import Foundation

@MainActor
final class SessionCoordinator {
    struct Dependencies {
        let startRecording: @MainActor (
            SessionID,
            @escaping @MainActor (SessionID, String) -> Void,
            @escaping @Sendable (RecordedAudio) -> Void,
            @escaping @Sendable (RecordedAudio) -> Void
        ) throws -> Void
        let stopRecording: @MainActor () -> Void
        let cancelRecording: @MainActor (SessionID) -> Void
        let finishPreview: @MainActor (SessionID) async -> String
        let cancelPreview: @MainActor (SessionID) async -> Void
        let transcribe: @MainActor (URL) async throws -> TranscriptionResult
        let clean: @MainActor (String) throws -> CleanResult
        let save: @MainActor (TranscriptRecord) throws -> Void
        let updateDeliveryStatus: @MainActor (SessionID, DeliveryStatus) throws -> Void
        let copy: @MainActor (String) -> Bool
        let scheduleSecondaryRemoval: @MainActor (
            TimeInterval,
            @escaping @MainActor () -> Void
        ) -> Void
    }

    private struct Session {
        let id: SessionID
        let ordinal: SessionOrdinal
        let createdAt: Date
        var status: SessionStatus = .recording
        var durationMilliseconds = 0
        var previewText = ""
        var message = "Recording"
        var stopRequested = false
        var deliverySucceeded: Bool?
        var secondaryRemovalScheduled = false

        var isProcessing: Bool { status == .transcribing || status == .saving }
    }

    private let dependencies: Dependencies
    private let onSnapshot: (AppSnapshot) -> Void
    private var sessions: [SessionID: Session] = [:]
    private var mainSessionID: SessionID?
    private var recordingSessionID: SessionID?
    private var processingTasks: [SessionID: Task<Void, Never>] = [:]
    private var nextOrdinal: UInt64 = 1

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
            handleToggleRecording()
        case .cancelRecording:
            await cancelCurrentSession()
        }
    }

    func handleToggleRecording() {
        if let recordingSessionID {
            guard var session = sessions[recordingSessionID], !session.stopRequested else { return }
            session.stopRequested = true
            sessions[recordingSessionID] = session
            dependencies.stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard processingSessionCount < 3 else {
            publishSnapshot()
            return
        }
        if let mainSessionID, sessions[mainSessionID]?.isProcessing != true {
            sessions.removeValue(forKey: mainSessionID)
        }

        let session = Session(
            id: SessionID(rawValue: UUID()),
            ordinal: SessionOrdinal(rawValue: nextOrdinal),
            createdAt: Date()
        )
        nextOrdinal += 1
        sessions[session.id] = session
        mainSessionID = session.id
        recordingSessionID = session.id

        do {
            try dependencies.startRecording(
                session.id,
                { [weak self] sessionID, text in
                    self?.receivePreview(text, for: sessionID)
                },
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
            publishSnapshot()
        } catch {
            recordingSessionID = nil
            sessions.removeValue(forKey: session.id)
            Task { @MainActor [dependencies] in
                await dependencies.cancelPreview(session.id)
            }
            snapshot = AppSnapshot(status: .failed, elapsedMilliseconds: 0, previewText: "", message: "Could not start recording.")
        }
    }

    private func receivePreview(_ text: String, for sessionID: SessionID) {
        guard recordingSessionID == sessionID,
              var session = sessions[sessionID],
              session.status == .recording,
              text != session.previewText else { return }
        session.previewText = text
        session.message = "实时草稿"
        sessions[sessionID] = session
        publishSnapshot()
    }

    private func receiveFinishedAudio(_ audio: RecordedAudio, for sessionID: SessionID) {
        guard recordingSessionID == sessionID,
              var session = sessions[sessionID],
              processingTasks[sessionID] == nil else { return }
        recordingSessionID = nil
        session.status = .transcribing
        session.durationMilliseconds = audio.durationMilliseconds
        session.message = "本地复核中"
        sessions[sessionID] = session
        publishSnapshot()

        processingTasks[sessionID] = Task { @MainActor [weak self] in
            await self?.process(audio, for: sessionID)
        }
    }

    private func receiveRecordingFailure(_ audio: RecordedAudio, for sessionID: SessionID) {
        guard recordingSessionID == sessionID,
              var session = sessions[sessionID],
              processingTasks[sessionID] == nil else { return }
        recordingSessionID = nil
        session.status = .saving
        session.durationMilliseconds = audio.durationMilliseconds
        session.message = "Saving"
        sessions[sessionID] = session
        publishSnapshot()

        processingTasks[sessionID] = Task { @MainActor [weak self] in
            guard let self else { return }
            await dependencies.cancelPreview(sessionID)
            guard let current = sessions[sessionID], !Task.isCancelled else {
                completeProcessing(sessionID)
                return
            }
            let record = TranscriptRecord(
                id: current.id,
                ordinal: current.ordinal,
                createdAt: current.createdAt,
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
            if save(record, for: sessionID, previewText: "") {
                finish(sessionID, with: .failed, previewText: "", message: "Recording failed.")
            }
            completeProcessing(sessionID)
        }
    }

    private func process(_ audio: RecordedAudio, for sessionID: SessionID) async {
        defer { completeProcessing(sessionID) }
        guard sessions[sessionID] != nil else { return }

        async let completedStreamingText = dependencies.finishPreview(sessionID)
        let senseVoiceResult: Result<TranscriptionResult, Error>
        do {
            senseVoiceResult = .success(try await dependencies.transcribe(audio.url))
        } catch {
            senseVoiceResult = .failure(error)
        }
        let streamingText = nonempty(await completedStreamingText)
        guard ownsProcessing(sessionID) else { return }

        let selectedText: String
        let detectedLanguages: [String]
        let finalSource: TranscriptFinalSource
        let senseVoiceText: String?
        switch senseVoiceResult {
        case let .success(result):
            selectedText = result.text
            detectedLanguages = result.detectedLanguage.map { [$0] } ?? []
            finalSource = .senseVoice
            senseVoiceText = result.text
        case .failure:
            guard let streamingText else {
                let session = sessions[sessionID]!
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
                if save(record, for: sessionID, previewText: "") {
                    finish(sessionID, with: .failed, previewText: "", message: "Transcription failed.")
                }
                return
            }
            selectedText = streamingText
            detectedLanguages = []
            finalSource = .streamingFallback
            senseVoiceText = nil
        }

        let cleaned: CleanResult
        do {
            cleaned = try dependencies.clean(selectedText)
        } catch {
            cleaned = CleanResult(text: selectedText, edits: [])
        }
        guard ownsProcessing(sessionID), let session = sessions[sessionID] else { return }

        let isEmpty = cleaned.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let record = TranscriptRecord(
            id: session.id,
            ordinal: session.ordinal,
            createdAt: session.createdAt,
            durationMilliseconds: audio.durationMilliseconds,
            detectedLanguages: detectedLanguages,
            originalText: selectedText,
            localCleanedText: cleaned.text,
            edits: cleaned.edits,
            deliveryStatus: .pending,
            outcome: isEmpty ? .noSpeech : .success,
            finalSource: finalSource,
            streamingText: streamingText,
            senseVoiceText: senseVoiceText
        )

        guard save(record, for: sessionID, previewText: cleaned.text) else { return }
        guard !isEmpty else {
            finish(sessionID, with: .cancelled, previewText: "", message: "No speech detected.")
            return
        }
        guard ownsProcessing(sessionID), sessions[sessionID]?.deliverySucceeded == nil else { return }

        let didCopy = dependencies.copy(cleaned.text)
        sessions[sessionID]?.deliverySucceeded = didCopy
        do {
            try dependencies.updateDeliveryStatus(session.id, didCopy ? .copied : .failed)
            finish(
                sessionID,
                with: didCopy ? .delivered : .failed,
                previewText: cleaned.text,
                message: didCopy ? "已复制 · 按 ⌘V 粘贴" : "Could not copy to clipboard."
            )
        } catch {
            finish(
                sessionID,
                with: didCopy ? .delivered : .failed,
                previewText: cleaned.text,
                message: didCopy ? "已复制，但未能记录复制状态" : "Could not update delivery status."
            )
        }
    }

    private func cancelCurrentSession() async {
        let sessionID: SessionID?
        if let recordingSessionID {
            sessionID = recordingSessionID
        } else if let mainSessionID, sessions[mainSessionID]?.isProcessing == true {
            sessionID = mainSessionID
        } else {
            sessionID = nil
        }
        guard let sessionID, var session = sessions[sessionID] else { return }

        processingTasks[sessionID]?.cancel()
        processingTasks.removeValue(forKey: sessionID)
        dependencies.cancelRecording(sessionID)
        await dependencies.cancelPreview(sessionID)
        if recordingSessionID == sessionID { recordingSessionID = nil }

        session.status = .cancelled
        session.durationMilliseconds = 0
        session.previewText = ""
        session.message = "Recording cancelled."
        sessions[sessionID] = session
        if mainSessionID == sessionID {
            publishSnapshot()
        } else {
            sessions.removeValue(forKey: sessionID)
            publishSnapshot()
        }
    }

    private func save(_ record: TranscriptRecord, for sessionID: SessionID, previewText: String) -> Bool {
        guard var session = sessions[sessionID], !Task.isCancelled else { return false }
        session.status = .saving
        session.previewText = previewText
        session.message = "Saving"
        sessions[sessionID] = session
        publishSnapshot()
        do {
            try dependencies.save(record)
            return ownsProcessing(sessionID)
        } catch {
            finish(sessionID, with: .failed, previewText: previewText, message: "Could not save transcript.")
            return false
        }
    }

    private func finish(_ sessionID: SessionID, with status: SessionStatus, previewText: String, message: String) {
        guard var session = sessions[sessionID] else { return }
        session.status = status
        session.previewText = previewText
        session.message = message
        sessions[sessionID] = session
        publishSnapshot()
    }

    private func completeProcessing(_ sessionID: SessionID) {
        processingTasks.removeValue(forKey: sessionID)
        if mainSessionID != sessionID,
           var session = sessions[sessionID],
           !session.isProcessing,
           !session.secondaryRemovalScheduled {
            session.secondaryRemovalScheduled = true
            let terminalStatus = session.status
            sessions[sessionID] = session
            dependencies.scheduleSecondaryRemoval(1.2) { [weak self] in
                guard let self,
                      self.mainSessionID != sessionID,
                      self.sessions[sessionID]?.status == terminalStatus else { return }
                self.sessions.removeValue(forKey: sessionID)
                self.publishSnapshot()
            }
        }
        publishSnapshot()
    }

    private func ownsProcessing(_ sessionID: SessionID) -> Bool {
        !Task.isCancelled && sessions[sessionID]?.isProcessing == true
    }

    private func publishSnapshot() {
        guard let mainSessionID, let main = sessions[mainSessionID] else { return }
        let secondary = sessions.values
            .filter { $0.id != mainSessionID }
            .sorted { $0.ordinal > $1.ordinal }
            .prefix(3)
            .map {
                SecondaryProcessingSnapshot(
                    id: $0.id,
                    status: $0.status,
                    previewText: $0.previewText,
                    message: $0.message
                )
            }
        snapshot = AppSnapshot(
            status: main.status,
            elapsedMilliseconds: main.durationMilliseconds,
            previewText: main.previewText,
            message: main.message,
            secondaryProcessing: Array(secondary),
            canStartRecording: processingSessionCount < 3
        )
    }

    private var processingSessionCount: Int {
        sessions.values.lazy.filter(\.isProcessing).count
    }

    private func nonempty(_ text: String) -> String? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
}
