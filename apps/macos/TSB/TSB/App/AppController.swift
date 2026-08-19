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
    let state: AppState

    private let coordinator: SessionCoordinator
    private let escapeMonitor: EscapeKeyMonitor
    private let modelError: String?
    private let notchOverlay: NotchOverlayPanel?
    private var intentTask: Task<Void, Never>?
    private var microphoneRequestLatch = MicrophoneRequestLatch()

    private lazy var hotkey = HotkeyService(
        eventSource: CarbonHotkeyEventSource(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)),
        onIntent: { [weak self] intent in
            self?.receive(intent)
        }
    )

    init() {
        let state = AppState()
        let recorder = AudioRecordingService()
        let store = TranscriptStore()
        let clipboard = ClipboardService.system
        let notchOverlay = NSScreen.findScreenForNotch().map(NotchOverlayPanel.init)
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

        let coordinator = SessionCoordinator(
            dependencies: .init(
                startRecording: { sessionID, onFinished in
                    try recorder.start(sessionID: sessionID, onFinished: onFinished)
                },
                stopRecording: {
                    recorder.stop()
                },
                cancelRecording: {
                    recorder.cancel()
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
                removeAudio: { url in
                    try FileManager.default.removeItem(at: url)
                }
            ),
            onSnapshot: { snapshot in
                state.snapshot = snapshot
                notchOverlay?.update(snapshot)
                if snapshot.status == .recording {
                    escapeMonitor.start()
                } else {
                    escapeMonitor.stop()
                }
            }
        )

        self.state = state
        self.coordinator = coordinator
        self.escapeMonitor = escapeMonitor
        self.modelError = modelError
        self.notchOverlay = notchOverlay
        escapeMonitor.onEscapePressed = { [weak self] in
            self?.dispatch(.cancelRecording)
        }
    }

    func start() {
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
    }

    func toggleForDevelopment() {
        receive(.toggleRecording)
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
                    self.dispatch(.toggleRecording)
                } else {
                    self.state.snapshot = AppSnapshot(status: .failed, elapsedMilliseconds: 0, previewText: "", message: "Microphone access is required to record.")
                    self.notchOverlay?.update(self.state.snapshot)
                }
            }
            return
        }
        dispatch(intent)
    }

    private func dispatch(_ intent: UserIntent) {
        intentTask?.cancel()
        intentTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self else { return }
            await coordinator.handle(intent)
        }
    }
}

private enum AppControllerError: Error {
    case modelUnavailable
}
