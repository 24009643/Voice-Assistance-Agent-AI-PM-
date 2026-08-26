import AppKit

/// Adapted from OpenDictation/Views/Notch/NotchWindow.swift (MIT, Copyright (c) 2025 Kenny).
final class NotchWindow: NSPanel {
    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func resize(to frame: NSRect) {
        setFrame(frame, display: true, animate: false)
    }
}
