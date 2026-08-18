import AppKit

/// Adapted from OpenDictation/Views/Notch/NotchWindow.swift (MIT, Copyright (c) 2025 Kenny).
final class NotchWindow: NSPanel {
    init(screen: NSScreen) {
        let frame = screen.frame
        let height = screen.safeAreaInsets.top
        super.init(
            contentRect: CGRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
