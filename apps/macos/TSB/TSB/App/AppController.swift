import AppKit
import AVFoundation
import Combine
import Foundation
import Carbon

enum TranscriptPolishDispatchError: Error, Equatable {
    case notEligible
}

@MainActor
final class AppState: ObservableObject {
    @Published var snapshot = AppSnapshot(status: .idle, elapsedMilliseconds: 0, previewText: "", message: nil)
}

@MainActor
final class AppController: ObservableObject {
    struct LivePreviewRuntime {
        let pipeline: LivePreviewPipeline
        let availability: LivePreviewAvailability
    }

    struct OrganizationDispatchSnapshot {
        let endpoint: OrganizationEndpointSettings
        let apiKey: String
    }

    let state: AppState

    private let coordinator: SessionCoordinator
    private let escapeMonitor: EscapeKeyMonitor
    private let modelError: String?
    private let bypassesMicrophonePermissionForDevelopment: Bool
    private let microphoneAuthorizationStatus: () -> AVAuthorizationStatus
    private let requestMicrophonePermission: (@escaping @MainActor (Bool) -> Void) -> Void
    private var notchOverlay: NotchOverlayPanel?
    private let manualCopy: (String) -> Bool
    private var screenParameterObserver: ScreenParameterObserver?
    private var recordingIntentTask: Task<Void, Never>?
    private var organizationIntentTask: Task<Void, Never>?
    private var intentTasks: [UUID: Task<Void, Never>] = [:]
    private var microphoneRequestLatch = MicrophoneRequestLatch()

    private lazy var hotkey = HotkeyService(
        eventSource: CarbonHotkeyEventSource(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)),
        onIntent: { [weak self] intent in
            self?.receive(intent)
        }
    )

    static func makeOrganizationDispatchSnapshot(
        localOnly: Bool = false,
        selectedCandidateIDs: Set<String>,
        loadSettings: () -> OrganizationSettings,
        loadAPIKey: (OrganizationEndpointSettings) throws -> String?
    ) throws -> OrganizationDispatchSnapshot {
        let settings = loadSettings()
        if localOnly && settings.endpoint?.isLoopback != true {
            throw OrganizationDispatchError.deterministicFallback
        }
        guard let endpoint = settings.endpoint,
              endpoint.isLoopback || settings.isRemoteDispatchEligible,
              selectedCandidateIDs.isEmpty
                || endpoint.isLoopback
                || settings.canSendUserSelectedHistorySummaries else {
            throw OrganizationDispatchError.authorizationRequired
        }
        if endpoint.isLoopback {
            return OrganizationDispatchSnapshot(endpoint: endpoint, apiKey: "")
        }
        guard let apiKey = try loadAPIKey(endpoint),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OrganizationDispatchError.authorizationRequired
        }
        return OrganizationDispatchSnapshot(endpoint: endpoint, apiKey: apiKey)
    }

    static func makePolishDispatchSnapshot(
        localOnly: Bool = false,
        loadSettings: () -> OrganizationSettings,
        loadAPIKey: (OrganizationEndpointSettings) throws -> String?
    ) throws -> OrganizationDispatchSnapshot {
        let settings = loadSettings()
        guard !localOnly, let endpoint = settings.endpoint else {
            throw TranscriptPolishDispatchError.notEligible
        }
        guard settings.isPolishDispatchEligible else {
            throw TranscriptPolishDispatchError.notEligible
        }
        if endpoint.isLoopback {
            return OrganizationDispatchSnapshot(endpoint: endpoint, apiKey: "")
        }
        guard let apiKey = try loadAPIKey(endpoint),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptPolishDispatchError.notEligible
        }
        return OrganizationDispatchSnapshot(endpoint: endpoint, apiKey: apiKey)
    }

    static func organizationIntent(for intent: IslandIntent) -> OrganizationIntent? {
        switch intent {
        case let .setLocalOnly(sessionID, enabled):
            .setLocalOnly(sessionID: sessionID, enabled: enabled)
        case let .cancelOrganization(sessionID, requestID):
            .cancel(sessionID: sessionID, requestID: requestID)
        case let .retryOrganization(sessionID, requestID):
            .retry(sessionID: sessionID, requestID: requestID)
        case let .generateLinks(sessionID, selectedRecordIDs):
            .enrichLinks(sessionID: sessionID, selectedRecordIDs: selectedRecordIDs)
        case .stopRecording, .cancelRecording, .copy, .openSettings, .openMicrophoneSettings:
            nil
        }
    }

    static func makeLivePreviewRuntime(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        applicationSupportDirectory: URL? = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
    ) -> LivePreviewRuntime {
        do {
            let location = try ParaformerModelLocation.resolvedLocation(
                environment: environment,
                applicationSupportDirectory: applicationSupportDirectory
            )
            return LivePreviewRuntime(
                pipeline: LivePreviewPipeline(modelLocation: location),
                availability: .available
            )
        } catch {
            return LivePreviewRuntime(
                pipeline: LivePreviewPipeline(modelLocation: nil),
                availability: .unavailable
            )
        }
    }

    init() {
        let state = AppState()
        let sessionsDirectory = TranscriptStore.defaultDirectory
        let recorder = AudioRecordingService(sessionsDirectory: sessionsDirectory)
        let store = TranscriptStore(directory: sessionsDirectory)
        let organizationSettingsStore = OrganizationSettingsStore()
        let organizationSecretStore = KeychainSecretStore()
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTest.XCTestCase") != nil
        let clipboard = ClipboardService.system
        var notchOverlay: NotchOverlayPanel?
        let escapeMonitor = EscapeKeyMonitor(
            eventSource: CarbonHotkeyEventSource(keyCode: UInt32(kVK_Escape), modifiers: 0)
        )

        let transcriber: SenseVoiceTranscriber?
        let modelError: String?
        do {
            transcriber = try SenseVoiceTranscriber(location: try SenseVoiceModelLocation.resolvedLocation())
            modelError = nil
        } catch {
            transcriber = nil
            modelError = "SenseVoice model is unavailable. Set TSB_SENSEVOICE_MODEL_DIR to a validated model directory."
        }

        let livePreviewRuntime = Self.makeLivePreviewRuntime()
        let livePreview = livePreviewRuntime.pipeline

        let coordinator = SessionCoordinator(
            dependencies: .init(
                startRecording: { sessionID, onPreview, onPreviewUnavailable, onLevel, onFinished, onFailed in
                    let feed = livePreview.start(
                        sessionID: sessionID,
                        onPreview: onPreview,
                        onPreviewUnavailable: onPreviewUnavailable
                    )
                    try recorder.start(
                        sessionID: sessionID,
                        onPCMChunk: feed,
                        onLevel: onLevel,
                        onFailed: onFailed,
                        onFinished: onFinished
                    )
                },
                stopRecording: {
                    recorder.stop()
                },
                cancelRecording: { sessionID in
                    recorder.cancel(sessionID: sessionID)
                },
                finishPreview: { sessionID in
                    await livePreview.finish(sessionID: sessionID)
                },
                cancelPreview: { sessionID in
                    await livePreview.cancel(sessionID: sessionID)
                },
                transcribe: { url in
                    guard let transcriber else { throw AppControllerError.modelUnavailable }
                    return try await transcriber.transcribe(wavURL: url)
                },
                clean: { source in
                    ConservativeCleaner().clean(source)
                },
                save: { record in
                    try store.save(record)
                },
                updateDeliveryStatus: { sessionID, status in
                    try store.updateDeliveryStatus(id: sessionID, to: status)
                },
                updateDelivery: { sessionID, status, receipt in
                    try store.updateDelivery(id: sessionID, status: status, receipt: receipt)
                },
                copy: { text in
                    clipboard.copy(text)
                },
                loadPersistedRecords: {
                    guard !isRunningTests else { return [] }
                    return try store.list()
                },
                updateOrganization: { sessionID, organization in
                    try store.updateOrganization(id: sessionID, to: organization)
                },
                currentOrganizationSettings: {
                    organizationSettingsStore.load()
                },
                currentTerminology: {
                    organizationSettingsStore.load().transcriptTerminology
                },
                polish: { request, localOnly, willDispatch in
                    let dispatch = try Self.makePolishDispatchSnapshot(
                        localOnly: localOnly,
                        loadSettings: organizationSettingsStore.load,
                        loadAPIKey: { try organizationSecretStore.load(for: $0) }
                    )
                    return try await TranscriptPolishClient(endpoint: TranscriptPolishEndpoint(
                        baseURL: dispatch.endpoint.baseURL,
                        model: dispatch.endpoint.model
                    )).polish(request, apiKey: dispatch.apiKey, onRequestPrepared: {
                        willDispatch(dispatch.endpoint, dispatch.endpoint.isLoopback ? .local : .remote)
                    })
                },
                historySuggestions: { sessionID in
                    try await Task.detached(priority: .userInitiated) {
                        let historyStore = TranscriptStore(directory: sessionsDirectory)
                        return try HistorySelector().suggestions(
                            for: historyStore.load(id: sessionID),
                            from: historyStore.list()
                        )
                    }.value
                },
                organize: { requestID, segments, suggestions, selectedCandidateIDs, localOnly, willDispatch in
                    let dispatch = try Self.makeOrganizationDispatchSnapshot(
                        localOnly: localOnly,
                        selectedCandidateIDs: selectedCandidateIDs,
                        loadSettings: organizationSettingsStore.load,
                        loadAPIKey: { try organizationSecretStore.load(for: $0) }
                    )
                    try willDispatch(dispatch.endpoint)
                    return try await OrganizationClient(endpoint: OrganizationEndpoint(
                        baseURL: dispatch.endpoint.baseURL,
                        model: dispatch.endpoint.model
                    )).organize(
                        requestID: requestID,
                        segments: segments,
                        historySuggestions: suggestions,
                        userSelectedCandidateIDs: selectedCandidateIDs,
                        apiKey: dispatch.apiKey
                    )
                },
                scheduleSecondaryRemoval: { delay, action in
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        action()
                    }
                }
            ),
            livePreviewAvailability: livePreviewRuntime.availability,
            onSnapshot: { snapshot in
                state.snapshot = snapshot
                notchOverlay?.update(snapshot)
                if snapshot.status != .recording {
                    escapeMonitor.stop()
                }
            }
        )

        self.state = state
        self.coordinator = coordinator
        self.escapeMonitor = escapeMonitor
        self.modelError = modelError
        self.bypassesMicrophonePermissionForDevelopment = false
        self.microphoneAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .audio)
        }
        self.requestMicrophonePermission = { completion in
            MicrophonePermission.request(completion)
        }
        self.notchOverlay = nil
        self.manualCopy = { clipboard.copy($0) }
        self.screenParameterObserver = nil
        notchOverlay = NSScreen.findScreenForNotch().map { screen in
            NotchOverlayPanel(screen: screen) { [weak self] intent in
                self?.receive(intent)
            }
        }
        self.notchOverlay = notchOverlay
        notchOverlay?.update(state.snapshot)
        screenParameterObserver = ScreenParameterObserver { [weak self] in
            guard let screen = NSScreen.findScreenForNotch() else { return }
            self?.notchOverlay?.reattach(to: screen)
        }
        escapeMonitor.onEscapePressed = { [weak self] in
            self?.dispatch(.cancelRecording)
        }
    }

#if DEBUG
    init(
        state: AppState,
        coordinator: SessionCoordinator,
        modelError: String? = nil,
        microphoneAuthorizationStatus: @escaping () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .audio)
        },
        requestMicrophonePermission: @escaping (@escaping @MainActor (Bool) -> Void) -> Void = {
            MicrophonePermission.request($0)
        }
    ) {
        self.state = state
        self.coordinator = coordinator
        self.escapeMonitor = EscapeKeyMonitor(
            eventSource: CarbonHotkeyEventSource(keyCode: UInt32(kVK_Escape), modifiers: 0)
        )
        self.modelError = modelError
        self.bypassesMicrophonePermissionForDevelopment = true
        self.microphoneAuthorizationStatus = microphoneAuthorizationStatus
        self.requestMicrophonePermission = requestMicrophonePermission
        self.notchOverlay = nil
        self.manualCopy = { _ in false }
        self.screenParameterObserver = nil
    }

    func enqueueBarrierForDevelopment(_ action: @escaping @MainActor () async -> Void) {
        enqueueRecording(action)
    }

    func enqueueOrganizationBarrierForDevelopment(_ action: @escaping @MainActor () async -> Void) {
        enqueueOrganizationIntent(action)
    }

    func dispatchOrganizationForDevelopment(_ intent: OrganizationIntent) {
        dispatch(intent)
    }

    func startRecordingForDevelopment() -> SessionCoordinator.DevelopmentWorkIdentity? {
        coordinator.startRecordingForDevelopment()
    }

    func stopRecordingForDevelopment(sessionID: SessionID) {
        coordinator.stopRecording(sessionID: sessionID)
    }

    func developmentWorkIdentity(
        sessionID: SessionID
    ) -> SessionCoordinator.DevelopmentWorkIdentity? {
        coordinator.developmentWorkIdentity(sessionID: sessionID)
    }

    func cancelDevelopmentWork(_ identity: SessionCoordinator.DevelopmentWorkIdentity) -> Bool {
        coordinator.cancelDevelopmentWork(identity)
    }

    func isDevelopmentWorkDrained(_ identity: SessionCoordinator.DevelopmentWorkIdentity) -> Bool {
        coordinator.isDevelopmentWorkDrained(identity)
    }
#endif

    func start() {
        screenParameterObserver?.start()
        coordinator.recoverInterruptedOrganizations()
        if let error = hotkey.start() {
            state.snapshot = AppSnapshot(status: .failed, elapsedMilliseconds: 0, previewText: "", message: error.message)
            notchOverlay?.update(state.snapshot)
            return
        }
        if let modelError {
            state.snapshot = AppSnapshot(status: .failed, elapsedMilliseconds: 0, previewText: "", message: modelError)
            notchOverlay?.update(state.snapshot)
        }
    }

    func stop() {
        for task in intentTasks.values {
            task.cancel()
        }
        recordingIntentTask = nil
        organizationIntentTask = nil
        intentTasks.removeAll()
        coordinator.shutdown()
        hotkey.stop()
        escapeMonitor.stop()
        screenParameterObserver?.stop()
    }

    func cancelPendingPolishAfterRevoke() {
        coordinator.cancelPendingPolishAfterRevoke()
    }

    func toggleForDevelopment() {
        guard bypassesMicrophonePermissionForDevelopment else {
            receive(.toggleRecording)
            return
        }
        enqueueRecording { [weak self] in
            self?.coordinator.handleToggleRecording()
        }
    }

    func toggleRecordingFromUI() {
        receive(.toggleRecording)
    }

    func startRecordingFromUI() {
        startRecordingIfPossible()
    }

    func stopRecordingFromUI(sessionID: SessionID) {
        enqueueRecording { [weak self] in
            self?.coordinator.stopRecording(sessionID: sessionID)
        }
    }

    func cancelRecordingFromUI() {
        receive(.cancelRecording)
    }

    func cancelRecordingFromUI(sessionID: SessionID) {
        enqueueRecording { [weak self] in
            await self?.coordinator.cancelRecording(sessionID: sessionID)
        }
    }

    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }

    private func receive(_ intent: UserIntent) {
        guard modelError == nil else {
            state.snapshot = AppSnapshot(status: .failed, elapsedMilliseconds: 0, previewText: "", message: modelError)
            return
        }

        switch intent {
        case .cancelRecording:
            dispatch(intent)
        case .toggleRecording:
            if state.snapshot.status == .recording {
                dispatch(intent)
            } else {
                startRecordingIfPossible()
            }
        }
    }

    private func startRecordingIfPossible() {
        guard modelError == nil else {
            publishModelRequirement()
            return
        }
        guard state.snapshot.status != .recording, state.snapshot.canStartRecording else { return }
        switch MicrophonePermission.decision(for: microphoneAuthorizationStatus()) {
        case .proceed:
            dispatchRecordingStart()
        case .request:
            guard microphoneRequestLatch.begin() else { return }
            requestMicrophonePermission { [weak self] granted in
                guard let self else { return }
                self.microphoneRequestLatch.finish()
                if granted {
                    self.startRecordingIfPossible()
                } else {
                    self.publishMicrophoneRequirement()
                }
            }
        case .openSettings:
            publishMicrophoneRequirement()
        }
    }

    private func publishModelRequirement() {
        state.snapshot = AppSnapshot(
            status: .failed,
            elapsedMilliseconds: 0,
            previewText: "",
            message: modelError
        )
        notchOverlay?.update(state.snapshot)
    }

    private func publishMicrophoneRequirement() {
        state.snapshot = AppSnapshot(
            status: .failed,
            elapsedMilliseconds: 0,
            previewText: "",
            message: "Microphone access is required to record."
        )
        notchOverlay?.update(state.snapshot)
    }

    private func receive(_ intent: IslandIntent) {
        if let organizationIntent = Self.organizationIntent(for: intent) {
            dispatch(organizationIntent)
            return
        }
        switch intent {
        case let .stopRecording(sessionID):
            enqueueRecording { [weak self] in
                self?.coordinator.stopRecording(sessionID: sessionID)
            }
        case let .cancelRecording(sessionID):
            enqueueRecording { [weak self] in
                await self?.coordinator.cancelRecording(sessionID: sessionID)
            }
        case let .copy(text):
            enqueueRecording { [weak self] in
                _ = self?.manualCopy(text)
            }
        case .openSettings:
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case .openMicrophoneSettings:
            openMicrophoneSettings()
        case .setLocalOnly, .cancelOrganization, .retryOrganization, .generateLinks:
            break
        }
    }

    static func startRecordingAfterEscapePreflight(
        startEscape: @MainActor () -> HotkeyStartError?,
        startRecording: @MainActor () -> Void
    ) -> HotkeyStartError? {
        if let error = startEscape() { return error }
        startRecording()
        return nil
    }

    private func dispatchRecordingStart() {
        enqueueRecording { [weak self] in
            guard let self else { return }
            let error = Self.startRecordingAfterEscapePreflight(
                startEscape: { self.escapeMonitor.start() },
                startRecording: { _ = self.coordinator.startRecording() }
            )
            if let error {
                state.snapshot = AppSnapshot(
                    status: .failed,
                    elapsedMilliseconds: 0,
                    previewText: "",
                    message: error.message
                )
                notchOverlay?.update(state.snapshot)
            }
        }
    }

    private func dispatch(_ intent: UserIntent) {
        enqueueRecording { [weak self] in
            guard let self else { return }
            await coordinator.handle(intent)
        }
    }

    private func dispatch(_ intent: OrganizationIntent) {
        enqueueOrganizationIntent { [weak self] in
            guard let self else { return }
            await coordinator.handle(intent)
        }
    }

    private func enqueueRecording(_ action: @escaping @MainActor () async -> Void) {
        let previous = recordingIntentTask
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            defer { self?.intentTasks[id] = nil }
            await previous?.value
            guard !Task.isCancelled else { return }
            await action()
        }
        recordingIntentTask = task
        intentTasks[id] = task
    }

    private func enqueueOrganizationIntent(_ action: @escaping @MainActor () async -> Void) {
        let previous = organizationIntentTask
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            defer { self?.intentTasks[id] = nil }
            await previous?.value
            guard !Task.isCancelled else { return }
            await action()
        }
        organizationIntentTask = task
        intentTasks[id] = task
    }
}

private enum AppControllerError: Error {
    case modelUnavailable
}
