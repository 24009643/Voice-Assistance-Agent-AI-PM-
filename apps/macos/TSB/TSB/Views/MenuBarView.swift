import SwiftUI

struct MenuBarPresentation: Equatable {
    let isRecording: Bool
    let sessionID: SessionID?
    let recordingStatusText: String?

    static func make(for snapshot: AppSnapshot) -> Self {
        Self(
            isRecording: snapshot.status == .recording,
            sessionID: snapshot.sessionID,
            recordingStatusText: snapshot.status == .recording
                && snapshot.livePreviewAvailability == .unavailable
                ? "实时草稿不可用，停止后仍会生成全文"
                : nil
        )
    }
}

struct MenuBarView: View {
    @ObservedObject var state: AppState
    let startRecording: () -> Void
    let stopRecording: (SessionID) -> Void
    let cancelRecording: (SessionID) -> Void
    let openMicrophoneSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        let presentation = MenuBarPresentation.make(for: state.snapshot)
        if presentation.isRecording, let sessionID = presentation.sessionID {
            Button("停止录音  ⌥Space") { stopRecording(sessionID) }
            Button("取消录音  Esc") { cancelRecording(sessionID) }
        } else {
            Button("开始录音  ⌥Space", action: startRecording)
        }
        if let recordingStatusText = presentation.recordingStatusText {
            Text(recordingStatusText)
        }
        if state.snapshot.message == "Microphone access is required to record." {
            Button("打开麦克风设置", action: openMicrophoneSettings)
        }
        SettingsLink { Text("设置") }
        Divider()
        Button("退出 TSB", action: quit)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        switch state.snapshot.status {
        case .recording:
            Label("TSB Recording", systemImage: "waveform")
        case .transcribing, .saving:
            Label("TSB Processing", systemImage: "ellipsis.circle")
        case .idle, .delivered, .failed, .cancelled:
            Label("TSB Ready", systemImage: "circle.fill")
        }
    }
}
