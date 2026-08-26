import AppKit
import SwiftUI

@MainActor
final class ScreenParameterObserver {
    private let center: NotificationCenter
    private let onChange: () -> Void
    private var token: NSObjectProtocol?

    init(center: NotificationCenter = .default, onChange: @escaping () -> Void) {
        self.center = center
        self.onChange = onChange
    }

    func start() {
        guard token == nil else { return }
        token = center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange() }
        }
    }

    func stop() {
        guard let token else { return }
        center.removeObserver(token)
        self.token = nil
    }

    deinit {
        MainActor.assumeIsolated { stop() }
    }
}

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
    private var screen: NSScreen
    private var screenWidth: CGFloat
    private var hasHardwareNotch: Bool
    private let hardwareNotchOverride: Bool?
    private let onIntent: (IslandIntent) -> Void
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private var window: NotchWindow?
    private var hostingView: NSHostingView<IslandView>?
    private var generation = OverlayGeneration(0)
    private var currentPresentation: IslandPresentation?
    private var currentSnapshot: AppSnapshot?
    private var latestResultSnapshot: AppSnapshot?
    private var isCollapsed = false

    convenience init(screen: NSScreen, onIntent: @escaping (IslandIntent) -> Void) {
        self.init(
            screen: screen,
            onIntent: onIntent,
            schedule: { delay, action in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { action() }
            }
        )
    }

    convenience init(
        screen: NSScreen,
        hasHardwareNotch: Bool,
        onIntent: @escaping (IslandIntent) -> Void
    ) {
        self.init(
            screen: screen,
            onIntent: onIntent,
            schedule: { delay, action in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { action() }
            },
            hasHardwareNotch: hasHardwareNotch
        )
    }

    init(
        screen: NSScreen,
        onIntent: @escaping (IslandIntent) -> Void,
        schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void,
        hasHardwareNotch: Bool? = nil
    ) {
        self.screen = screen
        self.screenWidth = screen.visibleFrame.width
        self.hardwareNotchOverride = hasHardwareNotch
        self.hasHardwareNotch = hasHardwareNotch ?? (screen.isBuiltin && screen.hasNotch)
        self.onIntent = onIntent
        self.schedule = schedule
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    var presentedMode: IslandMode? {
        currentPresentation?.mode
    }

    var presentedLayout: IslandLayout? {
        currentPresentation?.layout
    }

    var presentedSize: CGSize? {
        currentPresentation?.size
    }

    var presentedPrivacyReceiptText: String? {
        currentPresentation?.privacyReceiptText
    }

    var isIgnoringMouseEvents: Bool {
        window?.ignoresMouseEvents ?? true
    }

    var presentedFrame: CGRect? {
        window?.frame
    }

    var latestResultSessionID: SessionID? {
        latestResultSnapshot?.sessionID
    }

    func update(_ snapshot: AppSnapshot) {
        currentSnapshot = snapshot
        isCollapsed = false
        let presentation = IslandPresentation.make(
            for: snapshot,
            screenWidth: screenWidth,
            hasLatestResult: latestResultSnapshot != nil
        )
        if let secondary = snapshot.secondaryProcessing.first(where: Self.isCompletedResult) {
            let secondarySnapshot = AppSnapshot(
                sessionID: secondary.id,
                status: secondary.status,
                elapsedMilliseconds: 0,
                previewText: secondary.previewText,
                originalText: secondary.originalText,
                message: secondary.message,
                organizationPhase: secondary.organizationPhase,
                organizationRequestID: secondary.organizationRequestID,
                organizationReceipt: secondary.organizationReceipt,
                suggestedRecords: secondary.suggestedRecords
            )
            latestResultSnapshot = secondarySnapshot
        }
        if presentation.mode == .organized
            || presentation.mode == .localDelivered
            || (presentation.mode == .failed && !presentation.originalText.isEmpty) {
            latestResultSnapshot = snapshot
        }
        if presentation.mode == .idle, latestResultSnapshot == nil, !hasHardwareNotch {
            generation = generation.next()
            currentPresentation = presentation
            window?.ignoresMouseEvents = true
            window?.orderOut(nil)
            return
        }
        show(presentation)
        if let delay = presentation.autoHideDelay {
            scheduleHide(after: delay)
        }
    }

    func hide() {
        scheduleHide(after: 0.25)
    }

    func reattach(to screen: NSScreen, visibleWidth: CGFloat? = nil) {
        self.screen = screen
        screenWidth = visibleWidth ?? screen.visibleFrame.width
        hasHardwareNotch = hardwareNotchOverride ?? (screen.isBuiltin && screen.hasNotch)
        if isCollapsed {
            showIdle()
            return
        }
        if let currentSnapshot {
            let presentation = IslandPresentation.make(
                for: currentSnapshot,
                screenWidth: screenWidth,
                hasLatestResult: latestResultSnapshot != nil
            )
            if presentation.mode == .idle, latestResultSnapshot == nil, !hasHardwareNotch {
                currentPresentation = presentation
                window?.ignoresMouseEvents = true
                window?.orderOut(nil)
                return
            }
            show(presentation)
        }
    }

    private func show(_ presentation: IslandPresentation) {
        generation = generation.next()
        currentPresentation = presentation
        let frame = screen.islandFrame(for: presentation.size)
        if window == nil {
            window = NotchWindow(frame: frame)
        } else {
            window?.resize(to: frame)
        }
        window?.ignoresMouseEvents = presentation.controls.isEmpty
        let rootView = IslandView(
            presentation: presentation,
            onAction: { [weak self] action, selectedRecordIDs in
                self?.perform(action, selectedRecordIDs: selectedRecordIDs)
            }
        )
        if let hostingView {
            hostingView.rootView = rootView
        } else {
            let hostingView = NSHostingView(rootView: rootView)
            self.hostingView = hostingView
            window?.contentView = hostingView
        }
        window?.orderFrontRegardless()
    }

    func perform(_ action: IslandAction, selectedRecordIDs: Set<SessionID> = []) {
        guard currentPresentation?.controls.contains(where: { $0.action == action }) == true else { return }
        switch action {
        case .dismiss:
            guard currentPresentation?.mode != .idle else { return }
            showIdle()
        case .reopenLatest:
            if let latestResultSnapshot {
                isCollapsed = false
                currentSnapshot = latestResultSnapshot
                let latestResult = IslandPresentation.make(for: latestResultSnapshot, screenWidth: screenWidth)
                show(latestResult)
            }
        default:
            if let intent = currentPresentation?.intent(
                for: action,
                selectedRecordIDs: selectedRecordIDs
            ) {
                onIntent(intent)
            }
        }
    }

    private func showIdle() {
        isCollapsed = true
        let idle = IslandPresentation.make(
            for: AppSnapshot(status: .idle, elapsedMilliseconds: 0, previewText: "", message: nil),
            screenWidth: screenWidth,
            hasLatestResult: latestResultSnapshot != nil
        )
        show(idle)
    }

    private func scheduleHide(after delay: TimeInterval) {
        let callbackGeneration = generation
        schedule(delay) { [weak self] in
            guard let self, self.generation.accepts(callbackGeneration) else { return }
            self.showIdle()
        }
    }

    private static func isCompletedResult(_ item: SecondaryProcessingSnapshot) -> Bool {
        if case .organized = item.organizationPhase { return true }
        if case .failed = item.organizationPhase { return !item.previewText.isEmpty }
        return item.status == .delivered
            && item.organizationPhase != .queued
            && item.organizationPhase != .organizing
    }
}
