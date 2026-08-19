import AppKit
import SwiftUI

struct OverlayGeneration: Equatable, Sendable {
    private let rawValue: UInt

    init(_ rawValue: UInt) {
        self.rawValue = rawValue
    }

    func next() -> Self {
        Self(rawValue &+ 1)
    }

    func accepts(_ callbackGeneration: Self) -> Bool {
        self == callbackGeneration
    }
}

struct NotchPresentation: Equatable, Sendable {
    enum Tone: Equatable, Sendable {
        case neutral
        case success
        case warning
    }

    struct Secondary: Equatable, Sendable, Identifiable {
        let id: SessionID
        let text: String
        let tone: Tone
        let systemImage: String?
    }

    let label: String?
    let text: String
    let tone: Tone
    let systemImage: String?
    let accessibilityLabel: String?
    let autoHideDelay: TimeInterval?
    let secondary: [Secondary]

    static func make(for snapshot: AppSnapshot) -> Self? {
        guard snapshot.status != .idle else { return nil }
        let hasLiveDraft = snapshot.status == .recording && !snapshot.previewText.isEmpty
        let text = hasLiveDraft ? snapshot.previewText : snapshot.message ?? snapshot.previewText
        let secondary = snapshot.secondaryProcessing.prefix(3).map { item in
            let isSuccess = item.status == .delivered && item.message == "已复制 · 按 ⌘V 粘贴"
            let isWarning = item.status == .failed || item.status == .delivered
            return Secondary(
                id: item.id,
                text: isWarning ? item.message : (item.previewText.isEmpty ? item.message : item.previewText),
                tone: isSuccess ? .success : (isWarning ? .warning : .neutral),
                systemImage: isSuccess
                    ? "checkmark.circle.fill"
                    : (isWarning ? "exclamationmark.triangle.fill" : nil)
            )
        }

        if snapshot.status == .delivered, snapshot.message == "已复制 · 按 ⌘V 粘贴" {
            return Self(
                label: nil,
                text: text,
                tone: .success,
                systemImage: "checkmark.circle.fill",
                accessibilityLabel: "复制成功，按 Command V 粘贴",
                autoHideDelay: secondary.isEmpty ? 1.2 : nil,
                secondary: secondary
            )
        }

        if snapshot.status == .failed || snapshot.status == .delivered {
            return Self(
                label: nil,
                text: text,
                tone: .warning,
                systemImage: "exclamationmark.triangle.fill",
                accessibilityLabel: nil,
                autoHideDelay: nil,
                secondary: secondary
            )
        }

        return Self(
            label: hasLiveDraft ? "实时草稿" : nil,
            text: text,
            tone: .neutral,
            systemImage: nil,
            accessibilityLabel: nil,
            autoHideDelay: nil,
            secondary: secondary
        )
    }

    func windowHeight(notchHeight: CGFloat) -> CGFloat {
        max(notchHeight, 32) + CGFloat(secondary.count) * 36
    }
}

/// Adapted from OpenDictation/Views/Notch/NotchOverlayPanel.swift (MIT, Copyright (c) 2025 Kenny).
@MainActor
final class NotchOverlayPanel {
    private let screen: NSScreen
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private var window: NotchWindow?
    private var generation = OverlayGeneration(0)

    convenience init(screen: NSScreen) {
        self.init(screen: screen) { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { action() }
        }
    }

    init(
        screen: NSScreen,
        schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void
    ) {
        self.screen = screen
        self.schedule = schedule
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func update(_ snapshot: AppSnapshot) {
        guard let presentation = NotchPresentation.make(for: snapshot) else {
            hide()
            return
        }
        show(presentation)
        if let delay = presentation.autoHideDelay {
            scheduleHide(after: delay)
        }
    }

    private func show(_ presentation: NotchPresentation) {
        generation = generation.next()
        if window == nil {
            let window = NotchWindow(screen: screen)
            self.window = window
        }
        window?.resize(height: presentation.windowHeight(notchHeight: screen.notchSize.height))
        window?.contentView = NSHostingView(rootView: NotchOverlayView(notchSize: screen.notchSize, presentation: presentation))
        window?.orderFrontRegardless()
    }

    func hide() {
        scheduleHide(after: 0.25)
    }

    private func scheduleHide(after delay: TimeInterval) {
        let callbackGeneration = generation
        schedule(delay) { [weak self] in
            guard let self, self.generation.accepts(callbackGeneration) else { return }
            self.window?.orderOut(nil)
        }
    }
}

private struct NotchOverlayView: View {
    let notchSize: CGSize
    let presentation: NotchPresentation

    var body: some View {
        NotchShape()
            .fill(.black)
            .overlay {
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        if let systemImage = presentation.systemImage {
                            Image(systemName: systemImage)
                        }
                        if let label = presentation.label {
                            Text(label)
                                .foregroundStyle(.secondary)
                        }
                        Text(presentation.text)
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(foregroundColor)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(presentation.accessibilityLabel ?? presentation.text)
                    NotchWaveformView(audioLevel: 0)

                    ForEach(presentation.secondary) { item in
                        HStack(spacing: 4) {
                            if let systemImage = item.systemImage {
                                Image(systemName: systemImage)
                            }
                            Text(item.text)
                                .lineLimit(1)
                        }
                        .font(.caption2)
                        .foregroundStyle(foregroundColor(for: item.tone))
                        .frame(height: 36)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(item.text)
                    }
                }
            }
            .frame(
                width: max(notchSize.width, 280),
                height: presentation.windowHeight(notchHeight: notchSize.height)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var foregroundColor: Color {
        foregroundColor(for: presentation.tone)
    }

    private func foregroundColor(for tone: NotchPresentation.Tone) -> Color {
        switch tone {
        case .neutral: .white
        case .success: .green
        case .warning: .orange
        }
    }
}
