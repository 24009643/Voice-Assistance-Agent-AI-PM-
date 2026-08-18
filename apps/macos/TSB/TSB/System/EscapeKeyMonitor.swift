import AppKit

/// Adapted from OpenDictation/Core/Services/EscapeKeyMonitor.swift (MIT, Copyright (c) 2025 Kenny).
/// This local monitor deliberately needs no Accessibility permission.
@MainActor
final class EscapeKeyMonitor {
    var onEscapePressed: (() -> Void)?

    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.onEscapePressed?()
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
