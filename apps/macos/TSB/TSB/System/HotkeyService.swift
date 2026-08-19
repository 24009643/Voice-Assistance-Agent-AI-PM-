import AppKit
import Carbon

/// Adapted from OpenDictation/Core/Services/HotkeyService.swift (MIT, Copyright (c) 2025 Kenny).

enum UserIntent: Equatable {
    case toggleRecording
    case cancelRecording
}

enum HotkeyStartError: Equatable {
    case handlerInstallationFailed(Int32)
    case registrationFailed(Int32)

    var message: String {
        switch self {
        case .handlerInstallationFailed:
            "Could not install global hotkey handler."
        case .registrationFailed:
            "Could not register the global Option-Space hotkey."
        }
    }
}

@MainActor
protocol HotkeyEventSource: AnyObject {
    var onKeyDown: (() -> Void)? { get set }
    var onKeyUp: (() -> Void)? { get set }

    func start() -> HotkeyStartError?
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

    func start() -> HotkeyStartError? {
        eventSource.onKeyDown = { [weak self] in
            guard let self, !self.isKeyDown else { return }
            self.isKeyDown = true
            self.onIntent(.toggleRecording)
        }
        eventSource.onKeyUp = { [weak self] in
            self?.isKeyDown = false
        }
        if let error = eventSource.start() {
            eventSource.onKeyDown = nil
            eventSource.onKeyUp = nil
            isKeyDown = false
            return error
        }
        return nil
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

    func start() -> HotkeyStartError? {
        guard monitorStorage.monitors.isEmpty else { return nil }

        guard let keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if Self.matchesHotkey(event) {
                self?.onKeyDown?()
            }
            return event
        }) else { return .registrationFailed(-1) }

        guard let keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp, handler: { [weak self] event in
            if event.keyCode == 49 {
                self?.onKeyUp?()
            }
            return event
        }) else {
            NSEvent.removeMonitor(keyDownMonitor)
            return .registrationFailed(-1)
        }

        monitorStorage.monitors = [keyDownMonitor, keyUpMonitor]
        return nil
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

@MainActor
final class CarbonHotkeyEventSource: HotkeyEventSource {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private static let signature: OSType = 0x54534248 // TSBH
    private let keyCode: UInt32
    private let modifiers: UInt32
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    func start() -> HotkeyStartError? {
        guard hotkey == nil else { return nil }
        if let error = installHandlerIfNeeded() {
            return error
        }

        var registeredHotkey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: Self.signature, id: keyCode),
            GetApplicationEventTarget(),
            0,
            &registeredHotkey
        )
        guard status == noErr else {
            removeHandler()
            return .registrationFailed(Int32(status))
        }
        hotkey = registeredHotkey
        return nil
    }

    func stop() {
        if let hotkey {
            UnregisterEventHotKey(hotkey)
            self.hotkey = nil
        }
        removeHandler()
        onKeyDown = nil
        onKeyUp = nil
    }

    func handle(eventKind: UInt32) {
        if eventKind == UInt32(kEventHotKeyPressed) {
            onKeyDown?()
        } else if eventKind == UInt32(kEventHotKeyReleased) {
            onKeyUp?()
        }
    }

    private func installHandlerIfNeeded() -> HotkeyStartError? {
        guard handler == nil else { return nil }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let source = Unmanaged<CarbonHotkeyEventSource>.fromOpaque(userData).takeUnretainedValue()
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr,
                      identifier.signature == CarbonHotkeyEventSource.signature,
                      identifier.id == source.keyCode else { return noErr }
                source.handle(eventKind: UInt32(GetEventKind(event)))
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard status == noErr else {
            handler = nil
            return .handlerInstallationFailed(Int32(status))
        }
        return nil
    }

    private func removeHandler() {
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let hotkey {
                UnregisterEventHotKey(hotkey)
            }
            removeHandler()
        }
    }

}
