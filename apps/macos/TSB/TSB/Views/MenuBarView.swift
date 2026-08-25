import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: AppState
    let toggleRecording: () -> Void
    let cancelRecording: () -> Void
    let openMicrophoneSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        let recording = state.snapshot.status == .recording
        Button(recording ? "停止录音  ⌥Space" : "开始录音  ⌥Space", action: toggleRecording)
        if recording {
            Button("取消录音  Esc", action: cancelRecording)
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
