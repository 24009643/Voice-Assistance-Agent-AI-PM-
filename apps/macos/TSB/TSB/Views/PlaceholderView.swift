import SwiftUI

struct PlaceholderView: View {
    @ObservedObject var state: AppState
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if let presentation = NotchPresentation.make(for: state.snapshot) {
                HStack(spacing: 6) {
                    if let systemImage = presentation.systemImage {
                        Image(systemName: systemImage)
                    }
                    Text(presentation.statusText)
                }
                .foregroundStyle(foregroundColor(for: presentation.tone))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(presentation.statusText)
            }

            if !state.snapshot.previewText.isEmpty {
                Text(state.snapshot.previewText)
                    .textSelection(.enabled)
                    .lineLimit(6)
                    .accessibilityLabel(state.snapshot.previewText)
            }

            ForEach(state.snapshot.secondaryProcessing) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(secondaryTitle(for: item))
                        .font(.caption)
                        .foregroundStyle(secondaryColor(for: item))
                    if !secondaryText(for: item).isEmpty {
                        Text(secondaryText(for: item))
                            .lineLimit(2)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            Button(actionTitle, action: onToggle)
                .disabled(!allowsToggle)
            Text("Option-Space toggles recording. Escape cancels while recording.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 360, alignment: .leading)
        .padding()
    }

    private var title: String {
        switch state.snapshot.status {
        case .idle: "Ready"
        case .recording: "Recording"
        case .transcribing, .saving: "Processing"
        case .delivered: "Copied"
        case .failed: "Needs attention"
        case .cancelled: "Cancelled"
        }
    }

    private var actionTitle: String {
        if modelIsUnavailable { return "Unavailable" }
        if state.snapshot.status != .recording && !state.snapshot.canStartRecording {
            return "3 reviews in progress"
        }
        return state.snapshot.status == .recording ? "Stop recording" : "Start recording"
    }

    private var allowsToggle: Bool {
        !modelIsUnavailable
            && (state.snapshot.status == .recording || state.snapshot.canStartRecording)
    }

    private var modelIsUnavailable: Bool {
        state.snapshot.status == .failed && state.snapshot.message?.hasPrefix("SenseVoice model is unavailable") == true
    }

    private func foregroundColor(for tone: NotchPresentation.Tone) -> Color {
        switch tone {
        case .neutral: .secondary
        case .success: .green
        case .warning: .orange
        }
    }

    private func secondaryTitle(for item: SecondaryProcessingSnapshot) -> String {
        switch item.status {
        case .delivered: "已完成"
        case .failed: "需要处理"
        default: "本地复核中"
        }
    }

    private func secondaryText(for item: SecondaryProcessingSnapshot) -> String {
        switch item.status {
        case .delivered, .failed: item.message
        default: item.previewText
        }
    }

    private func secondaryColor(for item: SecondaryProcessingSnapshot) -> Color {
        switch item.status {
        case .delivered: .green
        case .failed: .orange
        default: .secondary
        }
    }
}
