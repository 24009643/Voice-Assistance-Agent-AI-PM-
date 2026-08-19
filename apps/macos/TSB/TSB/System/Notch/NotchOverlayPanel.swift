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

    let text: String
    let tone: Tone
    let systemImage: String?
    let accessibilityLabel: String?
    let autoHideDelay: TimeInterval?

    static func make(for snapshot: AppSnapshot) -> Self? {
        guard snapshot.status != .idle else { return nil }
        let text = snapshot.message ?? snapshot.previewText

        if snapshot.status == .delivered, snapshot.message == "已复制 · 按 ⌘V 粘贴" {
            return Self(
                text: text,
                tone: .success,
                systemImage: "checkmark.circle.fill",
                accessibilityLabel: "复制成功，按 Command V 粘贴",
                autoHideDelay: 1.2
            )
        }

        if snapshot.status == .failed || snapshot.status == .delivered {
            return Self(
                text: text,
                tone: .warning,
                systemImage: "exclamationmark.triangle.fill",
                accessibilityLabel: nil,
                autoHideDelay: nil
            )
        }

        return Self(
            text: text,
            tone: .neutral,
            systemImage: nil,
            accessibilityLabel: nil,
            autoHideDelay: nil
        )
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
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        if let systemImage = presentation.systemImage {
                            Image(systemName: systemImage)
                        }
                        Text(presentation.text)
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(foregroundColor)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(presentation.accessibilityLabel ?? presentation.text)
                    NotchWaveformView(audioLevel: 0)
                }
            }
            .frame(width: max(notchSize.width, 180), height: max(notchSize.height, 32))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var foregroundColor: Color {
        switch presentation.tone {
        case .neutral: .white
        case .success: .green
        case .warning: .orange
        }
    }
}
