import SwiftUI

struct IslandView: View {
    let presentation: IslandPresentation
    let onAction: (IslandAction, Set<SessionID>) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedChamber = IslandChamber.original
    @State private var selectedRecordIDs: Set<SessionID> = []

    var body: some View {
        ZStack {
            NotchShape(bottomCornerRadius: presentation.mode == .idle ? 14 : 20)
                .fill(.ultraThinMaterial)
            NotchShape(bottomCornerRadius: presentation.mode == .idle ? 14 : 20)
                .fill(Color.black.opacity(0.82))
            NotchShape(bottomCornerRadius: presentation.mode == .idle ? 14 : 20)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)

            content
        }
        .frame(width: presentation.size.width, height: presentation.size.height)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .animation(Self.animation(reduceMotion: reduceMotion), value: presentation.size)
        .animation(Self.animation(reduceMotion: reduceMotion), value: presentation.mode)
        .onChange(of: presentation.suggestions.map(\.id)) { _, availableIDs in
            selectedRecordIDs.formIntersection(Set(availableIDs))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch presentation.mode {
        case .idle:
            idleContent
        case .recording:
            recordingContent
        case .organized:
            organizedContent
        case .localDelivered, .organizing, .failed:
            statusContent
        }
    }

    private var idleContent: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.white.opacity(0.8))
                .frame(width: 5, height: 5)
            if control(for: .reopenLatest) != nil {
                actionButton(.reopenLatest)
            } else {
                Text("TSB")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .accessibilityLabel(presentation.accessibilityLabel)
            }
        }
        .padding(.horizontal, 12)
    }

    private var recordingContent: some View {
        HStack(spacing: 12) {
            NotchWaveformView(audioLevel: presentation.audioLevel)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text(presentation.draft.isEmpty ? "说点什么…" : presentation.draft)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .accessibilityLabel(presentation.draft.isEmpty ? "等待实时草稿" : presentation.draft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actionButton(.setLocalOnly(!isLocalOnly))
            actionButton(.stopRecording, prominent: true)
        }
        .padding(.horizontal, 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private var statusContent: some View {
        HStack(spacing: 10) {
            if presentation.mode == .organizing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在整理")
            } else if let systemImage = presentation.systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(statusColor)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                let detailText = Self.statusDetailText(for: presentation)
                if !detailText.isEmpty {
                    Text(detailText)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.accessibilityLabel)

            ForEach(compactActions, id: \.self) { action in
                actionButton(action, prominent: isPrimary(action))
            }
        }
        .padding(.horizontal, 14)
    }

    private var organizedContent: some View {
        VStack(spacing: 4) {
            if presentation.layout == .singleChamber {
                Picker("结果分舱", selection: $selectedChamber) {
                    ForEach(IslandChamber.allCases, id: \.self) { chamber in
                        Text(chamber.title).tag(chamber)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("原文、要点、关联分舱")
                .padding(.horizontal, 10)
                .padding(.top, 6)
                chamber(selectedChamber)
            } else {
                HStack(spacing: 0) {
                    ForEach(IslandChamber.allCases, id: \.self) { item in
                        chamber(item)
                        if item != .connections {
                            Divider().overlay(.white.opacity(0.1))
                        }
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            actionButton(.dismiss, icon: "chevron.up")
                .padding(6)
        }
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func chamber(_ chamber: IslandChamber) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(chamber.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                actionButton(.copyChamber(chamber), icon: "doc.on.doc")
            }

            ScrollView {
                chamberBody(chamber)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func chamberBody(_ chamber: IslandChamber) -> some View {
        switch chamber {
        case .original:
            Text(presentation.originalText.isEmpty ? "暂无原文" : presentation.originalText)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))
                .textSelection(.enabled)
        case .points:
            if presentation.numberedPoints.isEmpty {
                emptyText("没有可靠要点")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(presentation.numberedPoints.indices, id: \.self) { index in
                        let point = presentation.numberedPoints[index]
                        Text("\(point.number). \(point.text)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.76))
                    }
                }
            }
        case .connections:
            connectionsBody
        }
    }

    @ViewBuilder
    private var connectionsBody: some View {
        if presentation.knownRecordLinks.isEmpty,
           presentation.speculativeConnections.isEmpty,
           presentation.suggestions.isEmpty {
            emptyText("暂无可靠关联")
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(presentation.knownRecordLinks.indices, id: \.self) { index in
                    Label(presentation.knownRecordLinks[index].reason, systemImage: "link")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.76))
                }
                ForEach(presentation.speculativeConnections.indices, id: \.self) { index in
                    let connection = presentation.speculativeConnections[index]
                    HStack(alignment: .top, spacing: 5) {
                        Text(connection.label)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.22), in: Capsule())
                            .foregroundStyle(.orange)
                            .accessibilityLabel("推测")
                        Text(connection.statement)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.76))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("推测，\(connection.statement)，\(connection.detail)")
                }
                ForEach(presentation.suggestions) { suggestion in
                    Toggle(isOn: selection(for: suggestion.id)) {
                        Text(suggestion.summary)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .toggleStyle(.checkbox)
                    .foregroundStyle(.white.opacity(0.76))
                    .accessibilityLabel("选择本地建议，\(suggestion.summary)")
                }
                if control(for: .generateLinks) != nil {
                    actionButton(.generateLinks, prominent: true)
                        .disabled(selectedRecordIDs.isEmpty)
                }
            }
        }
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.5))
    }

    private func actionButton(
        _ action: IslandAction,
        prominent: Bool = false,
        icon: String? = nil
    ) -> some View {
        Group {
            if let control = control(for: action) {
                if prominent {
                    Button {
                        activate(action)
                    } label: {
                        buttonLabel(control, icon: icon)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel(control.accessibilityLabel)
                } else {
                    Button {
                        activate(action)
                    } label: {
                        buttonLabel(control, icon: icon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(control.accessibilityLabel)
                }
            }
        }
    }

    @ViewBuilder
    private func buttonLabel(_ control: IslandControl, icon: String?) -> some View {
        if let icon {
            Image(systemName: icon)
        } else {
            Text(control.title)
        }
    }

    private func activate(_ action: IslandAction) {
        switch action {
        case let .selectChamber(chamber):
            selectedChamber = chamber
        default:
            onAction(action, selectedRecordIDs)
        }
    }

    private func control(for action: IslandAction) -> IslandControl? {
        presentation.controls.first { $0.action == action }
    }

    private var compactActions: [IslandAction] {
        presentation.controls.map(\.action)
    }

    private var isLocalOnly: Bool {
        presentation.controls.contains { $0.action == .setLocalOnly(false) }
    }

    private func isPrimary(_ action: IslandAction) -> Bool {
        switch action {
        case .retryOrganization, .cancelOrganization:
            true
        default:
            false
        }
    }

    private func selection(for id: SessionID) -> Binding<Bool> {
        Binding(
            get: { selectedRecordIDs.contains(id) },
            set: { selected in
                if selected {
                    selectedRecordIDs.insert(id)
                } else {
                    selectedRecordIDs.remove(id)
                }
            }
        )
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 20).onEnded { value in
            let horizontal = value.translation.width
            let vertical = value.translation.height
            if presentation.layout == .singleChamber, abs(horizontal) > abs(vertical) {
                moveChamber(for: horizontal)
            } else if vertical > 28,
                      abs(vertical) > abs(horizontal),
                      control(for: .reopenLatest) != nil {
                activate(.reopenLatest)
            }
        }
    }

    private func moveChamber(for horizontalTranslation: CGFloat) {
        guard let index = IslandChamber.allCases.firstIndex(of: selectedChamber) else { return }
        let offset = horizontalTranslation < 0 ? 1 : -1
        let next = min(max(index + offset, 0), IslandChamber.allCases.count - 1)
        activate(.selectChamber(IslandChamber.allCases[next]))
    }

    private var statusColor: Color {
        switch presentation.tone {
        case .neutral: .white
        case .success: .green
        case .warning: .orange
        }
    }

    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(response: 0.28, dampingFraction: 0.86)
    }

    static func statusDetailText(for presentation: IslandPresentation) -> String {
        presentation.draft
    }
}
