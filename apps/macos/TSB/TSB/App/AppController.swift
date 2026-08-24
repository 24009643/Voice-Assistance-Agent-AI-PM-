import AppKit
import Combine
import Foundation
import Carbon

@MainActor
final class AppState: ObservableObject {
    @Published var snapshot = AppSnapshot(status: .idle, elapsedMilliseconds: 0, previewText: "", message: nil)
}

@MainActor
final class AppController: ObservableObject {
    struct OrganizationDispatchSnapshot {
        let endpoint: OrganizationEndpointSettings
        let apiKey: String
    }

    let state: AppState

    private let coordinator: SessionCoordinator
    private let escapeMonitor: EscapeKeyMonitor
    private let modelError: String?
    private let bypassesMicrophonePermissionForDevelopment: Bool
    private var notchOverlay: NotchOverlayPanel?
    private let manualCopy: (String) -> Bool
    private var screenParameterObserver: ScreenParameterObserver?
    private var intentTask: Task<Void, Never>?
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
        case .stopRecording, .copy:
            nil
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
            transcriber = try SenseVoiceTranscriber(location: try SenseVoiceModelLocation.developmentLocation())
            modelError = nil
        } catch {
            transcriber = nil
            modelError = "SenseVoice model is unavailable. Set TSB_SENSEVOICE_MODEL_DIR to a validated model directory."
        }

        let previewTranscriber = try? ParaformerPreviewTranscriber(
            location: ParaformerModelLocation.developmentLocation()
        )
        let livePreview = LivePreviewPipeline(transcriber: previewTranscriber)

        let coordinator = SessionCoordinator(
            dependencies: .init(
                startRecording: { sessionID, onPreview, onLevel, onFinished, onFailed in
                    let feed = livePreview.start(sessionID: sessionID, onPreview: onPreview)
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
                historySuggestions: { sessionID in
                    try HistorySelector().suggestions(for: store.load(id: sessionID), from: store.list())
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
    init(state: AppState, coordinator: SessionCoordinator) {
        self.state = state
        self.coordinator = coordinator
        self.escapeMonitor = EscapeKeyMonitor(
            eventSource: CarbonHotkeyEventSource(keyCode: UInt32(kVK_Escape), modifiers: 0)
        )
        self.modelError = nil
        self.bypassesMicrophonePermissionForDevelopment = true
        self.notchOverlay = nil
        self.manualCopy = { _ in false }
        self.screenParameterObserver = nil
    }

    func enqueueBarrierForDevelopment(_ action: @escaping @MainActor () async -> Void) {
        enqueue(action)
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
        intentTask?.cancel()
        intentTask = nil
        hotkey.stop()
        escapeMonitor.stop()
        screenParameterObserver?.stop()
    }

    func toggleForDevelopment() {
        guard bypassesMicrophonePermissionForDevelopment else {
            receive(.toggleRecording)
            return
        }
        enqueue { [weak self] in
            self?.coordinator.handleToggleRecording()
        }
    }

    private func receive(_ intent: UserIntent) {
        guard modelError == nil else {
            state.snapshot = AppSnapshot(status: .failed, elapsedMilliseconds: 0, previewText: "", message: modelError)
            return
        }

        guard intent != .toggleRecording || MicrophonePermission.isGranted else {
            guard microphoneRequestLatch.begin() else { return }
            MicrophonePermission.request { [weak self] granted in
                guard let self else { return }
                self.microphoneRequestLatch.finish()
                if granted {
                    self.receive(.toggleRecording)
                } else {
                    self.state.snapshot = AppSnapshot(status: .failed, elapsedMilliseconds: 0, previewText: "", message: "Microphone access is required to record.")
                    self.notchOverlay?.update(self.state.snapshot)
                }
            }
            return
        }
        switch intent {
        case .cancelRecording:
            dispatch(intent)
        case .toggleRecording:
            switch state.snapshot.status {
            case .recording:
                dispatch(intent)
            case .idle, .transcribing, .saving, .delivered, .failed, .cancelled:
                guard state.snapshot.canStartRecording else { return }
                dispatchRecordingStart()
            }
        }
    }

    private func receive(_ intent: IslandIntent) {
        if let organizationIntent = Self.organizationIntent(for: intent) {
            dispatch(organizationIntent)
            return
        }
        switch intent {
        case let .stopRecording(sessionID):
            enqueue { [weak self] in
                self?.coordinator.stopRecording(sessionID: sessionID)
            }
        case let .copy(text):
            enqueue { [weak self] in
                _ = self?.manualCopy(text)
            }
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
        enqueue { [weak self] in
            guard let self else { return }
            let error = Self.startRecordingAfterEscapePreflight(
                startEscape: { self.escapeMonitor.start() },
                startRecording: { self.coordinator.handleToggleRecording() }
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
        enqueue { [weak self] in
            guard let self else { return }
            await coordinator.handle(intent)
        }
    }

    private func dispatch(_ intent: OrganizationIntent) {
        enqueue { [weak self] in
            guard let self else { return }
            await coordinator.handle(intent)
        }
    }

    private func enqueue(_ action: @escaping @MainActor () async -> Void) {
        let previous = intentTask
        intentTask = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { return }
            await action()
        }
    }
}

private enum AppControllerError: Error {
    case modelUnavailable
}
