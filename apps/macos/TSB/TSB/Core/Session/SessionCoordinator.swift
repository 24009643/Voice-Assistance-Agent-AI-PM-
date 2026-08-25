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
        let historySuggestions: @MainActor (SessionID) async throws -> HistorySuggestions
        let organize: @MainActor (
            UUID,
            [TextSegment],
            HistorySuggestions,
            Set<String>,
            Bool,
            @MainActor (OrganizationEndpointSettings) throws -> Void
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
        var lastOrganizationSelectedRecordIDs: Set<SessionID> = []
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
        let historySuggestions: HistorySuggestions
        let selectedCandidateIDs: Set<String>
        let selectedRecordIDs: [SessionID]
        let localOnly: Bool
        var provider: String
        var model: String
        var providerKind: ProviderKind
    }

    private let dependencies: Dependencies
    private let livePreviewAvailability: LivePreviewAvailability
    private let onSnapshot: (AppSnapshot) -> Void
    private var sessions: [SessionID: Session] = [:]
    private var mainSessionID: SessionID?
    private var recordingSessionID: SessionID?
    private var processingTasks: [SessionID: Task<Void, Never>] = [:]
    private var previewCancellationTasks: [SessionID: Task<Void, Never>] = [:]
    private var organizationQueue: [OrganizationJob] = []
    private var activeOrganization: (job: OrganizationJob, task: Task<Void, Never>)?
    private var latestTerminalSessionID: SessionID?
    private var nextOrdinal: UInt64 = 1

    private(set) var snapshot = AppSnapshot(status: .idle, elapsedMilliseconds: 0, previewText: "", message: nil) {
        didSet { onSnapshot(snapshot) }
    }

    init(
        dependencies: Dependencies,
        livePreviewAvailability: LivePreviewAvailability = .available,
        onSnapshot: @escaping (AppSnapshot) -> Void
    ) {
        self.dependencies = dependencies
        self.livePreviewAvailability = livePreviewAvailability
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
        case let .cancel(sessionID, requestID):
            cancelOrganization(for: sessionID, expectedRequestID: requestID)
        case let .retry(sessionID, requestID):
            guard let session = sessions[sessionID], session.organizationRequestID == requestID else { return }
            await enqueueOrganization(for: sessionID, selectedRecordIDs: session.lastOrganizationSelectedRecordIDs)
        case let .enrichLinks(sessionID, selectedRecordIDs):
            await enqueueOrganization(for: sessionID, selectedRecordIDs: selectedRecordIDs)
        }
    }

    func shutdown() {
        activeOrganization?.task.cancel()
        activeOrganization = nil
        organizationQueue.removeAll()

        let incompleteSessionIDs = sessions.values.compactMap {
            $0.status == .recording || $0.isProcessing ? $0.id : nil
        }
        for sessionID in incompleteSessionIDs {
            processingTasks[sessionID]?.cancel()
            dependencies.cancelRecording(sessionID)
            _ = trackPreviewCancellation(sessionID)
            sessions.removeValue(forKey: sessionID)
        }
        recordingSessionID = nil
        processingTasks.removeAll()
    }

    func handleToggleRecording() {
        if let recordingSessionID {
            stopRecording(sessionID: recordingSessionID)
        } else {
            _ = startRecording()
        }
    }

    func stopRecording(sessionID: SessionID) {
        guard recordingSessionID == sessionID,
              var session = sessions[sessionID],
              !session.stopRequested else { return }
        session.stopRequested = true
        sessions[sessionID] = session
        dependencies.stopRecording()
    }

#if DEBUG
    struct DevelopmentWorkIdentity: Equatable {
        let sessionID: SessionID
        let organizationRequestID: UUID?
    }

    func startRecordingForDevelopment() -> DevelopmentWorkIdentity? {
        guard recordingSessionID == nil else { return nil }
        guard let sessionID = startRecording() else { return nil }
        return DevelopmentWorkIdentity(sessionID: sessionID, organizationRequestID: nil)
    }

    func developmentWorkIdentity(sessionID: SessionID) -> DevelopmentWorkIdentity? {
        guard let session = sessions[sessionID] else { return nil }
        return DevelopmentWorkIdentity(
            sessionID: sessionID,
            organizationRequestID: session.organizationRequestID
        )
    }

    func cancelDevelopmentWork(_ identity: DevelopmentWorkIdentity) -> Bool {
        guard let session = sessions[identity.sessionID] else {
            return identity.organizationRequestID == nil
        }
        guard session.organizationRequestID == identity.organizationRequestID else { return false }
        if recordingSessionID == identity.sessionID || processingTasks[identity.sessionID] != nil {
            beginSessionCancellation(identity.sessionID)
        }
        if let requestID = identity.organizationRequestID {
            cancelOrganization(for: identity.sessionID, expectedRequestID: requestID)
        }
        return true
    }

    func isDevelopmentWorkDrained(_ identity: DevelopmentWorkIdentity) -> Bool {
        recordingSessionID != identity.sessionID
            && processingTasks[identity.sessionID] == nil
            && previewCancellationTasks[identity.sessionID] == nil
            && activeOrganization?.job.sessionID != identity.sessionID
            && !organizationQueue.contains { $0.sessionID == identity.sessionID }
    }
#endif

    private func startRecording() -> SessionID? {
        guard processingSessionCount < 3 else {
            publishSnapshot()
            return nil
        }
        let previousMainID = mainSessionID
        var previousMainToRetain: SessionID?
        if let previousMainID {
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
            mainSessionID = previousMainID.flatMap { sessions[$0] == nil ? nil : $0 }
            _ = trackPreviewCancellation(session.id)
            snapshot = AppSnapshot(status: .failed, elapsedMilliseconds: 0, previewText: "", message: "Could not start recording.")
        }
        return session.id
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
            senseVoiceText = result.text
            if let senseVoiceText = nonempty(result.text) {
                selectedText = senseVoiceText
                detectedLanguages = result.detectedLanguage.map { [$0] } ?? []
                finalSource = .senseVoice
            } else if let streamingText {
                selectedText = streamingText
                detectedLanguages = []
                finalSource = .streamingFallback
            } else {
                selectedText = result.text
                detectedLanguages = result.detectedLanguage.map { [$0] } ?? []
                finalSource = .senseVoice
            }
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
                await refreshHistorySuggestions(for: sessionID)
                await enqueueOrganization(for: sessionID, selectedRecordIDs: [])
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
        guard let sessionID else { return }
        let previewCancellation = beginSessionCancellation(sessionID)
        await previewCancellation?.value
    }

    @discardableResult
    private func beginSessionCancellation(_ sessionID: SessionID) -> Task<Void, Never>? {
        guard var session = sessions[sessionID] else { return nil }

        processingTasks[sessionID]?.cancel()
        dependencies.cancelRecording(sessionID)
        if recordingSessionID == sessionID { recordingSessionID = nil }

        let previewCancellation = trackPreviewCancellation(sessionID)

        session.status = .cancelled
        session.durationMilliseconds = 0
        session.audioLevel = 0
        session.previewText = ""
        session.message = "Recording cancelled."
        session.resultRetainedForDisplay = true
        sessions[sessionID] = session
        if mainSessionID != sessionID {
            scheduleSecondaryRemovalIfEligible(sessionID)
        }
        publishSnapshot()
        return previewCancellation
    }

    private func trackPreviewCancellation(_ sessionID: SessionID) -> Task<Void, Never> {
        if let existing = previewCancellationTasks[sessionID] {
            return existing
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await dependencies.cancelPreview(sessionID)
            previewCancellationTasks.removeValue(forKey: sessionID)
        }
        previewCancellationTasks[sessionID] = task
        return task
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

    private func enqueueOrganization(
        for sessionID: SessionID,
        selectedRecordIDs requestedRecordIDs: Set<SessionID>
    ) async {
        guard var session = sessions[sessionID], let transcript = session.transcript else { return }
        let requestID = UUID()
        session.organizationRequestID = requestID
        session.lastOrganizationSelectedRecordIDs = requestedRecordIDs
        session.secondaryRemovalScheduled = false
        sessions[sessionID] = session
        let settings = dependencies.currentOrganizationSettings()
        let useDeterministic = session.localOnly && settings.endpoint?.isLoopback != true
        guard useDeterministic || settings.endpoint?.isLoopback == true || settings.isRemoteDispatchEligible else {
            session.organizationPhase = .authorizationRequired
            session.resultRetainedForDisplay = true
            session.secondaryRemovalScheduled = false
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
                session.secondaryRemovalScheduled = false
                sessions[sessionID] = session
                publishSnapshot()
                scheduleSecondaryRemovalIfEligible(sessionID)
                return
            }
            guard let available = try? await dependencies.historySuggestions(sessionID) else {
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
        let endpoint = settings.endpoint
        let providerKind: ProviderKind = useDeterministic || endpoint?.isLoopback == true ? .local : .remote
        let job = OrganizationJob(
            sessionID: sessionID,
            requestID: requestID,
            segments: segments,
            historySuggestions: suggestions,
            selectedCandidateIDs: selectedCandidateIDs,
            selectedRecordIDs: selectedRecordIDs,
            localOnly: session.localOnly,
            provider: useDeterministic ? "deterministic" : "openai-compatible",
            model: useDeterministic ? "local-points" : endpoint?.model ?? "",
            providerKind: providerKind
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
        guard sessions[job.sessionID]?.organizationRequestID == job.requestID else {
            startNextOrganizationIfNeeded()
            return
        }
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runOrganization(job)
        }
        activeOrganization = (job, task)
    }

    private func runOrganization(_ job: OrganizationJob) async {
        var dispatchJob = job
        do {
            let output: OrganizationOutput
            do {
                output = try await dependencies.organize(
                    job.requestID,
                    job.segments,
                    job.historySuggestions,
                    job.selectedCandidateIDs,
                    job.localOnly,
                    { [weak self] endpoint in
                        guard let self else { throw CancellationError() }
                        dispatchJob = self.organizationJob(job, for: endpoint)
                        try self.prepareRemoteDispatch(dispatchJob)
                    }
                )
            } catch OrganizationDispatchError.deterministicFallback {
                dispatchJob.provider = "deterministic"
                dispatchJob.model = "local-points"
                dispatchJob.providerKind = .local
                try prepareRemoteDispatch(dispatchJob)
                output = try DeterministicOrganizer().organize(segments: dispatchJob.segments)
            }
            guard !Task.isCancelled,
                  var session = sessions[dispatchJob.sessionID],
                  session.organizationRequestID == dispatchJob.requestID else {
                completeOrganizationSlot(job)
                return
            }
            let record = organizationRecord(for: dispatchJob, state: .succeeded, output: output)
            do {
                try dependencies.updateOrganization(dispatchJob.sessionID, record)
                session.organizationPhase = .organized(record)
            } catch {
                session.organizationPhase = .failed("Could not save organization result.")
            }
            session.resultRetainedForDisplay = true
            session.secondaryRemovalScheduled = false
            sessions[dispatchJob.sessionID] = session
        } catch is CancellationError {
            completeOrganizationSlot(job)
            return
        } catch OrganizationDispatchError.authorizationRequired {
            finishFailedOrganization(
                dispatchJob,
                errorCode: "authorization_required",
                persistedPhase: .authorizationRequired,
                persistenceFailureMessage: "Authorization changed, but could not save failure state."
            )
        } catch OrganizationRuntimeError.dispatchStateWriteFailed {
            finishFailedOrganization(
                dispatchJob,
                errorCode: "state_persistence_failed",
                persistedPhase: .failed("Could not save organization state."),
                persistenceFailureMessage: "Could not save organization failure state; pending state remains on disk."
            )
        } catch {
            guard !Task.isCancelled,
                  sessions[dispatchJob.sessionID]?.organizationRequestID == dispatchJob.requestID else {
                completeOrganizationSlot(job)
                return
            }
            finishFailedOrganization(
                dispatchJob,
                errorCode: "organization_failed",
                persistedPhase: .failed("Organization failed."),
                persistenceFailureMessage: "Organization failed, but could not save failure state."
            )
        }
        publishSnapshot()
        scheduleSecondaryRemovalIfEligible(dispatchJob.sessionID)
        completeOrganizationSlot(job)
    }

    private func cancelOrganization(for sessionID: SessionID, expectedRequestID: UUID) {
        guard var session = sessions[sessionID],
              session.organizationRequestID == expectedRequestID,
              session.hasOrganizationWork else { return }
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
        }
        let invalidationID = UUID()
        session.organizationRequestID = invalidationID
        session.organizationPhase = .failed("Organization cancelled.")
        session.resultRetainedForDisplay = true
        session.secondaryRemovalScheduled = false
        if let cancelledJob {
            let failed = OrganizationRecord(
                requestID: invalidationID,
                inputTextSHA256: OrganizationValidator.inputTextSHA256(for: cancelledJob.segments),
                state: .failed,
                provider: cancelledJob.provider,
                model: cancelledJob.model,
                providerKind: cancelledJob.providerKind,
                selectedRecordIDs: cancelledJob.selectedRecordIDs,
                sentCharacterCount: cancelledJob.segments.reduce(0) { $0 + $1.text.count },
                output: nil,
                errorCode: "cancelled",
                updatedAt: Date()
            )
            do {
                try dependencies.updateOrganization(sessionID, failed)
            } catch {
                session.organizationPhase = .failed("Organization cancelled, but could not save cancellation state.")
            }
        }
        sessions[sessionID] = session
        publishSnapshot()
        scheduleSecondaryRemovalIfEligible(sessionID)
        if activeOrganization?.job.sessionID != sessionID || activeOrganization?.job.requestID != oldRequestID {
            startNextOrganizationIfNeeded()
        }
    }

    private func organizationJob(_ job: OrganizationJob, for endpoint: OrganizationEndpointSettings) -> OrganizationJob {
        OrganizationJob(
            sessionID: job.sessionID,
            requestID: job.requestID,
            segments: job.segments,
            historySuggestions: job.historySuggestions,
            selectedCandidateIDs: job.selectedCandidateIDs,
            selectedRecordIDs: job.selectedRecordIDs,
            localOnly: job.localOnly,
            provider: "openai-compatible",
            model: endpoint.model,
            providerKind: endpoint.isLoopback ? .local : .remote
        )
    }

    private func prepareRemoteDispatch(_ job: OrganizationJob) throws {
        guard var session = sessions[job.sessionID], session.organizationRequestID == job.requestID else {
            throw CancellationError()
        }
        do {
            try dependencies.updateOrganization(job.sessionID, organizationRecord(for: job, state: .pending))
        } catch {
            throw OrganizationRuntimeError.dispatchStateWriteFailed
        }
        session.organizationPhase = .organizing
        session.secondaryRemovalScheduled = false
        sessions[job.sessionID] = session
        if let active = activeOrganization,
           active.job.sessionID == job.sessionID,
           active.job.requestID == job.requestID {
            activeOrganization = (job, active.task)
        }
        publishSnapshot()
    }

    private func finishFailedOrganization(
        _ job: OrganizationJob,
        errorCode: String,
        persistedPhase: OrganizationPhase,
        persistenceFailureMessage: String
    ) {
        guard var session = sessions[job.sessionID], session.organizationRequestID == job.requestID else { return }
        do {
            try dependencies.updateOrganization(
                job.sessionID,
                organizationRecord(for: job, state: .failed, errorCode: errorCode)
            )
            session.organizationPhase = persistedPhase
        } catch {
            session.organizationPhase = .failed(persistenceFailureMessage)
        }
        session.resultRetainedForDisplay = true
        session.secondaryRemovalScheduled = false
        sessions[job.sessionID] = session
    }

    private func completeOrganizationSlot(_ job: OrganizationJob) {
        if activeOrganization?.job.sessionID == job.sessionID,
           activeOrganization?.job.requestID == job.requestID {
            activeOrganization = nil
            scheduleSecondaryRemovalIfEligible(job.sessionID)
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
            sentCharacterCount: job.segments.reduce(0) { $0 + $1.text.count },
            output: output,
            errorCode: errorCode,
            updatedAt: Date()
        )
    }

    private func failOrganizationPreparation(_ sessionID: SessionID, message: String) {
        guard var session = sessions[sessionID] else { return }
        session.organizationPhase = .failed(message)
        session.resultRetainedForDisplay = true
        session.secondaryRemovalScheduled = false
        sessions[sessionID] = session
        publishSnapshot()
        scheduleSecondaryRemovalIfEligible(sessionID)
    }

    private func refreshHistorySuggestions(for sessionID: SessionID) async {
        guard var session = sessions[sessionID],
              let suggestions = try? await dependencies.historySuggestions(sessionID) else { return }
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
        let records: [TranscriptRecord]
        do {
            records = try dependencies.loadPersistedRecords()
        } catch {
            snapshot = AppSnapshot(
                status: .failed,
                elapsedMilliseconds: 0,
                previewText: "",
                message: "Could not inspect interrupted organization state."
            )
            return
        }
        var recoveryWriteFailed = false
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
                sentCharacterCount: organization.sentCharacterCount,
                output: nil,
                errorCode: "interrupted",
                updatedAt: Date()
            )
            do {
                try dependencies.updateOrganization(record.id, interrupted)
            } catch {
                recoveryWriteFailed = true
            }
        }
        if recoveryWriteFailed {
            snapshot = AppSnapshot(
                status: .failed,
                elapsedMilliseconds: 0,
                previewText: "",
                message: "Could not mark interrupted organization as failed."
            )
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
        retainAsLatestTerminalIfEligible(sessionID)
        guard mainSessionID != sessionID,
              var session = sessions[sessionID],
              !session.isProcessing,
              !hasOrganizationWork(sessionID, session: session),
              session.resultRetainedForDisplay,
              !session.secondaryRemovalScheduled else { return }
        session.secondaryRemovalScheduled = true
        let requestID = session.organizationRequestID
        let phase = session.organizationPhase
        sessions[sessionID] = session
        dependencies.scheduleSecondaryRemoval(1.2) { [weak self] in
            guard let self,
                  var current = self.sessions[sessionID],
                  current.organizationRequestID == requestID,
                  current.organizationPhase == phase else { return }
            current.secondaryRemovalScheduled = false
            self.sessions[sessionID] = current
            if self.latestTerminalSessionID == sessionID {
                self.publishSnapshot()
                return
            }
            guard self.mainSessionID != sessionID,
                  !current.isProcessing,
                  !self.hasOrganizationWork(sessionID, session: current),
                  current.resultRetainedForDisplay else { return }
            current.resultRetainedForDisplay = false
            self.sessions[sessionID] = current
            if self.canRemoveSession(sessionID) {
                self.sessions.removeValue(forKey: sessionID)
            }
            self.publishSnapshot()
        }
    }

    private func retainAsLatestTerminalIfEligible(_ sessionID: SessionID) {
        guard var session = sessions[sessionID],
              let transcript = session.transcript,
              !transcript.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !session.isProcessing,
              !hasOrganizationWork(sessionID, session: session) else { return }

        if let latestTerminalSessionID,
           let latest = sessions[latestTerminalSessionID],
           latest.ordinal > session.ordinal {
            session.resultRetainedForDisplay = false
            sessions[sessionID] = session
            if canRemoveSession(sessionID) {
                sessions.removeValue(forKey: sessionID)
            }
            return
        }

        if let previousID = latestTerminalSessionID, previousID != sessionID,
           var previous = sessions[previousID] {
            previous.resultRetainedForDisplay = false
            previous.secondaryRemovalScheduled = false
            sessions[previousID] = previous
            if canRemoveSession(previousID) {
                sessions.removeValue(forKey: previousID)
            }
        }
        latestTerminalSessionID = sessionID
        session.resultRetainedForDisplay = true
        sessions[sessionID] = session
    }

    private func canRemoveSession(_ sessionID: SessionID) -> Bool {
        guard let session = sessions[sessionID] else { return false }
        return session.status != .recording
            && !session.isProcessing
            && !hasOrganizationWork(sessionID, session: session)
            && !session.resultRetainedForDisplay
    }

    private func hasOrganizationWork(_ sessionID: SessionID, session: Session) -> Bool {
        session.hasOrganizationWork
            || activeOrganization?.job.sessionID == sessionID
            || organizationQueue.contains { $0.sessionID == sessionID }
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
                    originalText: $0.transcript?.originalText ?? "",
                    message: $0.message,
                    organizationPhase: $0.organizationPhase,
                    organizationRequestID: $0.organizationRequestID,
                    suggestedRecords: $0.suggestedRecords
                )
            }
        snapshot = AppSnapshot(
            sessionID: main.id,
            status: main.status,
            elapsedMilliseconds: main.durationMilliseconds,
            previewText: main.previewText,
            originalText: main.transcript?.originalText ?? "",
            message: main.message,
            audioLevel: main.audioLevel,
            livePreviewAvailability: livePreviewAvailability,
            organizationPhase: main.organizationPhase,
            organizationRequestID: main.organizationRequestID,
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
    case dispatchStateWriteFailed
}

enum OrganizationDispatchError: Error {
    case authorizationRequired
    case deterministicFallback
}
