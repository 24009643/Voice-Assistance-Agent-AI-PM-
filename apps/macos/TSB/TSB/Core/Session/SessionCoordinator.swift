import Foundation

@MainActor
final class SessionCoordinator {
    struct Dependencies {
        let startRecording: @MainActor (
            SessionID,
            @escaping @MainActor (SessionID, String) -> Void,
            @escaping @Sendable (Float) -> Void,
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
        let loadPersistedRecords: @MainActor () throws -> [TranscriptRecord]
        let updateOrganization: @MainActor (SessionID, OrganizationRecord) throws -> Void
        let currentOrganizationSettings: @MainActor () -> OrganizationSettings
        let historySuggestions: @MainActor (SessionID) throws -> HistorySuggestions
        let organize: @MainActor (
            OrganizationEndpointSettings,
            UUID,
            [TextSegment],
            HistorySuggestions,
            Set<String>
        ) async throws -> OrganizationOutput
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
        var audioLevel: Float = 0
        var lastAudioLevelUpdate: TimeInterval = -.infinity
        var stopRequested = false
        var deliverySucceeded: Bool?
        var transcript: TranscriptRecord?
        var localOnly = false
        var organizationPhase: OrganizationPhase = .notRequested
        var suggestedRecords: [SuggestedRecordSnapshot] = []
        var organizationRequestID: UUID?
        var resultRetainedForDisplay = false
        var secondaryRemovalScheduled = false

        var isProcessing: Bool { status == .transcribing || status == .saving }
        var hasOrganizationWork: Bool {
            organizationPhase == .queued || organizationPhase == .organizing
        }
    }

    private struct OrganizationJob {
        let sessionID: SessionID
        let requestID: UUID
        let segments: [TextSegment]
        let settings: OrganizationSettings
        let historySuggestions: HistorySuggestions
        let selectedCandidateIDs: Set<String>
        let selectedRecordIDs: [SessionID]
        let provider: String
        let model: String
        let providerKind: ProviderKind
        let useDeterministicOrganizer: Bool
    }

    private let dependencies: Dependencies
    private let onSnapshot: (AppSnapshot) -> Void
    private var sessions: [SessionID: Session] = [:]
    private var mainSessionID: SessionID?
    private var recordingSessionID: SessionID?
    private var processingTasks: [SessionID: Task<Void, Never>] = [:]
    private var organizationQueue: [OrganizationJob] = []
    private var activeOrganization: (job: OrganizationJob, task: Task<Void, Never>)?
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

    func handle(_ intent: OrganizationIntent) async {
        switch intent {
        case let .setLocalOnly(sessionID, enabled):
            setLocalOnly(enabled, for: sessionID)
        case let .cancel(sessionID):
            cancelOrganization(for: sessionID)
        case let .retry(sessionID):
            enqueueOrganization(for: sessionID, selectedRecordIDs: [])
        case let .enrichLinks(sessionID, selectedRecordIDs):
            enqueueOrganization(for: sessionID, selectedRecordIDs: selectedRecordIDs)
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
        var previousMainToRetain: SessionID?
        if let previousMainID = mainSessionID {
            if canRemoveSession(previousMainID) {
                sessions.removeValue(forKey: previousMainID)
            } else {
                previousMainToRetain = previousMainID
            }
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
        if let previousMainToRetain {
            scheduleSecondaryRemovalIfEligible(previousMainToRetain)
        }

        do {
            try dependencies.startRecording(
                session.id,
                { [weak self] sessionID, text in
                    self?.receivePreview(text, for: sessionID)
                },
                { [weak self] level in
                    Task { @MainActor [weak self] in
                        self?.receiveAudioLevel(level, for: session.id)
                    }
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

    private func receiveAudioLevel(_ rawLevel: Float, for sessionID: SessionID) {
        guard recordingSessionID == sessionID,
              var session = sessions[sessionID],
              session.status == .recording else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - session.lastAudioLevelUpdate >= 0.05 else { return }
        session.audioLevel = rawLevel.isFinite ? min(max(rawLevel, 0), 1) : 0
        session.lastAudioLevelUpdate = now
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
        session.audioLevel = 0
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
        session.audioLevel = 0
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
        sessions[sessionID]?.transcript = record
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
            if didCopy {
                refreshHistorySuggestions(for: sessionID)
                enqueueOrganization(for: sessionID, selectedRecordIDs: [])
            }
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
        session.audioLevel = 0
        session.previewText = ""
        session.message = "Recording cancelled."
        session.resultRetainedForDisplay = true
        sessions[sessionID] = session
        if mainSessionID == sessionID {
            publishSnapshot()
        } else {
            scheduleSecondaryRemovalIfEligible(sessionID)
            publishSnapshot()
        }
    }

    private func setLocalOnly(_ enabled: Bool, for sessionID: SessionID) {
        guard recordingSessionID == sessionID,
              var session = sessions[sessionID],
              session.status == .recording,
              !session.stopRequested else { return }
        session.localOnly = enabled
        session.organizationPhase = enabled ? .localOnly : .notRequested
        sessions[sessionID] = session
        publishSnapshot()
    }

    private func enqueueOrganization(for sessionID: SessionID, selectedRecordIDs requestedRecordIDs: Set<SessionID>) {
        guard var session = sessions[sessionID], let transcript = session.transcript else { return }
        let settings = dependencies.currentOrganizationSettings()
        let useDeterministic = session.localOnly
        guard useDeterministic || settings.endpoint?.isLoopback == true || settings.isRemoteDispatchEligible else {
            session.organizationPhase = .authorizationRequired
            session.resultRetainedForDisplay = true
            sessions[sessionID] = session
            publishSnapshot()
            scheduleSecondaryRemovalIfEligible(sessionID)
            return
        }

        let suggestions: HistorySuggestions
        let selectedCandidateIDs: Set<String>
        let selectedRecordIDs: [SessionID]
        if requestedRecordIDs.isEmpty {
            suggestions = HistorySuggestions(suggestedSummaries: [], localRecordByCandidateID: [:])
            selectedCandidateIDs = []
            selectedRecordIDs = []
        } else {
            guard settings.endpoint?.isLoopback == true || settings.canSendUserSelectedHistorySummaries else {
                session.organizationPhase = .authorizationRequired
                session.resultRetainedForDisplay = true
                sessions[sessionID] = session
                publishSnapshot()
                scheduleSecondaryRemovalIfEligible(sessionID)
                return
            }
            guard let available = try? dependencies.historySuggestions(sessionID) else {
                failOrganizationPreparation(sessionID, message: "Could not load history suggestions.")
                return
            }
            suggestions = available
            session.suggestedRecords = suggestedRecords(from: available)
            selectedCandidateIDs = Set(available.localRecordByCandidateID.compactMap {
                requestedRecordIDs.contains($0.value) ? $0.key : nil
            })
            selectedRecordIDs = available.localRecordByCandidateID.compactMap {
                selectedCandidateIDs.contains($0.key) ? $0.value : nil
            }.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
        }

        guard let segments = try? DeterministicOrganizer().segments(from: transcript.localCleanedText), !segments.isEmpty else {
            failOrganizationPreparation(sessionID, message: "Nothing to organize.")
            return
        }
        let requestID = UUID()
        let endpoint = settings.endpoint
        let providerKind: ProviderKind = useDeterministic || endpoint?.isLoopback == true ? .local : .remote
        let job = OrganizationJob(
            sessionID: sessionID,
            requestID: requestID,
            segments: segments,
            settings: settings,
            historySuggestions: suggestions,
            selectedCandidateIDs: selectedCandidateIDs,
            selectedRecordIDs: selectedRecordIDs,
            provider: useDeterministic ? "deterministic" : "openai-compatible",
            model: useDeterministic ? "local-points" : endpoint?.model ?? "",
            providerKind: providerKind,
            useDeterministicOrganizer: useDeterministic
        )
        let pending = organizationRecord(for: job, state: .pending)
        do {
            try dependencies.updateOrganization(sessionID, pending)
        } catch {
            failOrganizationPreparation(sessionID, message: "Could not save organization state.")
            return
        }

        session.organizationRequestID = requestID
        session.organizationPhase = .queued
        session.resultRetainedForDisplay = false
        session.secondaryRemovalScheduled = false
        sessions[sessionID] = session
        organizationQueue.removeAll { $0.sessionID == sessionID }
        organizationQueue.append(job)
        publishSnapshot()
        startNextOrganizationIfNeeded()
    }

    private func startNextOrganizationIfNeeded() {
        guard activeOrganization == nil, !organizationQueue.isEmpty else { return }
        let job = organizationQueue.removeFirst()
        guard var session = sessions[job.sessionID], session.organizationRequestID == job.requestID else {
            startNextOrganizationIfNeeded()
            return
        }
        session.organizationPhase = .organizing
        sessions[job.sessionID] = session
        publishSnapshot()
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runOrganization(job)
        }
        activeOrganization = (job, task)
    }

    private func runOrganization(_ job: OrganizationJob) async {
        do {
            let output: OrganizationOutput
            if job.useDeterministicOrganizer {
                output = try DeterministicOrganizer().organize(segments: job.segments)
            } else if let endpoint = job.settings.endpoint {
                output = try await dependencies.organize(
                    endpoint,
                    job.requestID,
                    job.segments,
                    job.historySuggestions,
                    job.selectedCandidateIDs
                )
            } else {
                throw OrganizationRuntimeError.missingEndpoint
            }
            guard !Task.isCancelled,
                  var session = sessions[job.sessionID],
                  session.organizationRequestID == job.requestID else {
                completeOrganizationSlot(job)
                return
            }
            let record = organizationRecord(for: job, state: .succeeded, output: output)
            do {
                try dependencies.updateOrganization(job.sessionID, record)
                session.organizationPhase = .organized(record)
                session.resultRetainedForDisplay = true
                sessions[job.sessionID] = session
            } catch {
                session.organizationPhase = .failed("Could not save organization result.")
                session.resultRetainedForDisplay = true
                sessions[job.sessionID] = session
            }
        } catch is CancellationError {
            completeOrganizationSlot(job)
            return
        } catch {
            guard !Task.isCancelled,
                  var session = sessions[job.sessionID],
                  session.organizationRequestID == job.requestID else {
                completeOrganizationSlot(job)
                return
            }
            let failed = organizationRecord(for: job, state: .failed, errorCode: "organization_failed")
            try? dependencies.updateOrganization(job.sessionID, failed)
            session.organizationPhase = .failed("Organization failed.")
            session.resultRetainedForDisplay = true
            sessions[job.sessionID] = session
        }
        publishSnapshot()
        scheduleSecondaryRemovalIfEligible(job.sessionID)
        completeOrganizationSlot(job)
    }

    private func cancelOrganization(for sessionID: SessionID) {
        guard var session = sessions[sessionID], session.hasOrganizationWork else { return }
        let oldRequestID = session.organizationRequestID
        let cancelledJob = activeOrganization.flatMap {
            $0.job.sessionID == sessionID && $0.job.requestID == oldRequestID ? $0.job : nil
        } ?? organizationQueue.first {
            $0.sessionID == sessionID && $0.requestID == oldRequestID
        }
        organizationQueue.removeAll { $0.sessionID == sessionID && $0.requestID == oldRequestID }
        if activeOrganization?.job.sessionID == sessionID,
           activeOrganization?.job.requestID == oldRequestID {
            activeOrganization?.task.cancel()
            activeOrganization = nil
        }
        let invalidationID = UUID()
        session.organizationRequestID = invalidationID
        session.organizationPhase = .failed("Organization cancelled.")
        session.resultRetainedForDisplay = true
        session.secondaryRemovalScheduled = false
        sessions[sessionID] = session
        if let cancelledJob {
            let failed = OrganizationRecord(
                requestID: invalidationID,
                inputTextSHA256: OrganizationValidator.inputTextSHA256(for: cancelledJob.segments),
                state: .failed,
                provider: cancelledJob.provider,
                model: cancelledJob.model,
                providerKind: cancelledJob.providerKind,
                selectedRecordIDs: cancelledJob.selectedRecordIDs,
                output: nil,
                errorCode: "cancelled",
                updatedAt: Date()
            )
            try? dependencies.updateOrganization(sessionID, failed)
        }
        publishSnapshot()
        scheduleSecondaryRemovalIfEligible(sessionID)
        startNextOrganizationIfNeeded()
    }

    private func completeOrganizationSlot(_ job: OrganizationJob) {
        if activeOrganization?.job.sessionID == job.sessionID,
           activeOrganization?.job.requestID == job.requestID {
            activeOrganization = nil
            startNextOrganizationIfNeeded()
        }
    }

    private func organizationRecord(
        for job: OrganizationJob,
        state: OrganizationPersistenceState,
        output: OrganizationOutput? = nil,
        errorCode: String? = nil
    ) -> OrganizationRecord {
        OrganizationRecord(
            requestID: job.requestID,
            inputTextSHA256: OrganizationValidator.inputTextSHA256(for: job.segments),
            state: state,
            provider: job.provider,
            model: job.model,
            providerKind: job.providerKind,
            selectedRecordIDs: job.selectedRecordIDs,
            output: output,
            errorCode: errorCode,
            updatedAt: Date()
        )
    }

    private func failOrganizationPreparation(_ sessionID: SessionID, message: String) {
        guard var session = sessions[sessionID] else { return }
        session.organizationPhase = .failed(message)
        session.resultRetainedForDisplay = true
        sessions[sessionID] = session
        publishSnapshot()
        scheduleSecondaryRemovalIfEligible(sessionID)
    }

    private func refreshHistorySuggestions(for sessionID: SessionID) {
        guard var session = sessions[sessionID],
              let suggestions = try? dependencies.historySuggestions(sessionID) else { return }
        session.suggestedRecords = suggestedRecords(from: suggestions)
        sessions[sessionID] = session
    }

    private func suggestedRecords(from suggestions: HistorySuggestions) -> [SuggestedRecordSnapshot] {
        suggestions.suggestedSummaries.compactMap { suggestion in
            suggestions.localRecordByCandidateID[suggestion.candidateID].map {
                SuggestedRecordSnapshot(id: $0, summary: suggestion.summary)
            }
        }
    }

    func recoverInterruptedOrganizations() {
        guard let records = try? dependencies.loadPersistedRecords() else { return }
        for record in records {
            guard let organization = record.organization, organization.state == .pending else { continue }
            let interrupted = OrganizationRecord(
                requestID: organization.requestID,
                inputTextSHA256: organization.inputTextSHA256,
                state: .failed,
                provider: organization.provider,
                model: organization.model,
                providerKind: organization.providerKind,
                selectedRecordIDs: organization.selectedRecordIDs,
                output: nil,
                errorCode: "interrupted",
                updatedAt: Date()
            )
            try? dependencies.updateOrganization(record.id, interrupted)
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
        session.resultRetainedForDisplay = true
        sessions[sessionID] = session
        publishSnapshot()
    }

    private func completeProcessing(_ sessionID: SessionID) {
        processingTasks.removeValue(forKey: sessionID)
        scheduleSecondaryRemovalIfEligible(sessionID)
        publishSnapshot()
    }

    private func scheduleSecondaryRemovalIfEligible(_ sessionID: SessionID) {
        guard mainSessionID != sessionID,
              var session = sessions[sessionID],
              !session.isProcessing,
              !session.hasOrganizationWork,
              session.resultRetainedForDisplay,
              !session.secondaryRemovalScheduled else { return }
        session.secondaryRemovalScheduled = true
        let requestID = session.organizationRequestID
        let phase = session.organizationPhase
        sessions[sessionID] = session
        dependencies.scheduleSecondaryRemoval(1.2) { [weak self] in
            guard let self,
                  self.mainSessionID != sessionID,
                  var current = self.sessions[sessionID],
                  current.organizationRequestID == requestID,
                  current.organizationPhase == phase,
                  !current.isProcessing,
                  !current.hasOrganizationWork,
                  current.resultRetainedForDisplay else { return }
            current.resultRetainedForDisplay = false
            self.sessions[sessionID] = current
            if self.canRemoveSession(sessionID) {
                self.sessions.removeValue(forKey: sessionID)
            }
            self.publishSnapshot()
        }
    }

    private func canRemoveSession(_ sessionID: SessionID) -> Bool {
        guard let session = sessions[sessionID] else { return false }
        return session.status != .recording
            && !session.isProcessing
            && !session.hasOrganizationWork
            && !session.resultRetainedForDisplay
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
                    message: $0.message,
                    organizationPhase: $0.organizationPhase,
                    suggestedRecords: $0.suggestedRecords
                )
            }
        snapshot = AppSnapshot(
            status: main.status,
            elapsedMilliseconds: main.durationMilliseconds,
            previewText: main.previewText,
            message: main.message,
            audioLevel: main.audioLevel,
            organizationPhase: main.organizationPhase,
            suggestedRecords: main.suggestedRecords,
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

private enum OrganizationRuntimeError: Error {
    case missingEndpoint
}
