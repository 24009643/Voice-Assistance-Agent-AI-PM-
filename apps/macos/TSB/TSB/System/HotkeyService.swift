import AppKit

/// Adapted from OpenDictation/Core/Services/HotkeyService.swift (MIT, Copyright (c) 2025 Kenny).

enum UserIntent: Equatable {
    case toggleRecording
}

@MainActor
protocol HotkeyEventSource: AnyObject {
    var onKeyDown: (() -> Void)? { get set }
    var onKeyUp: (() -> Void)? { get set }

    func start()
    func stop()
}

@MainActor
final class HotkeyService {
    private let eventSource: HotkeyEventSource
    private let onIntent: (UserIntent) -> Void
    private var isKeyDown = false

    init(eventSource: HotkeyEventSource, onIntent: @escaping (UserIntent) -> Void) {
        self.eventSource = eventSource
        self.onIntent = onIntent
    }

    func start() {
        eventSource.onKeyDown = { [weak self] in
            guard let self, !self.isKeyDown else { return }
            self.isKeyDown = true
            self.onIntent(.toggleRecording)
        }
        eventSource.onKeyUp = { [weak self] in
            self?.isKeyDown = false
        }
        eventSource.start()
    }

    func stop() {
        eventSource.onKeyDown = nil
        eventSource.onKeyUp = nil
        eventSource.stop()
        isKeyDown = false
    }
}

@MainActor
final class LocalHotkeyEventSource: HotkeyEventSource {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private let monitorStorage = MonitorStorage()

    func start() {
        guard monitorStorage.monitors.isEmpty else { return }

        guard let keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if Self.matchesHotkey(event) {
                self?.onKeyDown?()
            }
            return event
        }) else { return }

        guard let keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp, handler: { [weak self] event in
            if event.keyCode == 49 {
                self?.onKeyUp?()
            }
            return event
        }) else {
            NSEvent.removeMonitor(keyDownMonitor)
            return
        }

        monitorStorage.monitors = [keyDownMonitor, keyUpMonitor]
    }

    static func matchesHotkey(_ event: NSEvent) -> Bool {
        event.keyCode == 49 && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option
    }

    func stop() {
        monitorStorage.removeAll()
        onKeyDown = nil
        onKeyUp = nil
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
