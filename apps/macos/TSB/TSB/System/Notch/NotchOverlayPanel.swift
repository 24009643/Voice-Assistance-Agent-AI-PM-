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

/// Adapted from OpenDictation/Views/Notch/NotchOverlayPanel.swift (MIT, Copyright (c) 2025 Kenny).
@MainActor
final class NotchOverlayPanel {
    private let screen: NSScreen
    private var window: NotchWindow?
    private var generation = OverlayGeneration(0)

    init(screen: NSScreen) {
        self.screen = screen
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        generation = generation.next()
        if window == nil {
            let window = NotchWindow(screen: screen)
            window.contentView = NSHostingView(rootView: NotchOverlayView(notchSize: screen.notchSize))
            self.window = window
        }
        window?.orderFrontRegardless()
    }

    func hide() {
        let callbackGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.generation.accepts(callbackGeneration) else { return }
            self.window?.orderOut(nil)
        }
    }
}

private struct NotchOverlayView: View {
    let notchSize: CGSize

    var body: some View {
        NotchShape()
            .fill(.black)
            .overlay(NotchWaveformView(audioLevel: 0))
            .frame(width: max(notchSize.width, 180), height: max(notchSize.height, 32))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
