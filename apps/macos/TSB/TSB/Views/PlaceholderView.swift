import SwiftUI

struct PlaceholderView: View {
    @ObservedObject var state: AppState
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if let message = state.snapshot.message {
                Text(message)
                    .foregroundStyle(state.snapshot.status == .failed ? .red : .secondary)
            }

            if !state.snapshot.previewText.isEmpty {
                Text(state.snapshot.previewText)
                    .textSelection(.enabled)
                    .lineLimit(6)
            }

            Button(state.snapshot.status == .recording ? "Stop recording" : "Start recording", action: onToggle)
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
}
