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
                    Text(presentation.text)
                }
                .foregroundStyle(foregroundColor(for: presentation.tone))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(presentation.accessibilityLabel ?? presentation.text)
            }

            if !state.snapshot.previewText.isEmpty {
                Text(state.snapshot.status == .recording ? "实时草稿" : "本地结果")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(state.snapshot.previewText)
                    .textSelection(.enabled)
                    .lineLimit(6)
            }

            ForEach(state.snapshot.secondaryProcessing) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text("本地复核中")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !item.previewText.isEmpty {
                        Text(item.previewText)
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
        return state.snapshot.status == .recording ? "Stop recording" : "Start recording"
    }

    private var allowsToggle: Bool {
        !modelIsUnavailable
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
}
