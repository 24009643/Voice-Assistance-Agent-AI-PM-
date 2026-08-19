import AppKit

/// Adapted from OpenDictation/Core/Services/EscapeKeyMonitor.swift (MIT, Copyright (c) 2025 Kenny).
/// This local monitor deliberately needs no Accessibility permission.
@MainActor
final class EscapeKeyMonitor {
    var onEscapePressed: (() -> Void)?

    private let monitorStorage = MonitorStorage()

    func start() {
        guard monitorStorage.monitors.isEmpty else { return }
        guard let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }) else { return }
        monitorStorage.monitors = [monitor]
    }

    func stop() {
        monitorStorage.removeAll()
    }

    func handle(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == 53, let onEscapePressed else { return event }
        onEscapePressed()
        return nil
    }

    private final class MonitorStorage {
        var monitors: [Any] = []

        func removeAll() {
            monitors.forEach(NSEvent.removeMonitor)
            monitors.removeAll()
        }

        deinit {
            removeAll()
        }
    }
}
