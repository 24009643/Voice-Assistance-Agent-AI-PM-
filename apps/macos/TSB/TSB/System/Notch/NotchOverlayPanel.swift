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
    private let onIntent: (IslandIntent) -> Void
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private var window: NotchWindow?
    private var hostingView: NSHostingView<IslandView>?
    private var generation = OverlayGeneration(0)
    private var currentPresentation: IslandPresentation?
    private var latestResult: IslandPresentation?

    convenience init(screen: NSScreen, onIntent: @escaping (IslandIntent) -> Void) {
        self.init(
            screen: screen,
            onIntent: onIntent,
            schedule: { delay, action in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { action() }
            }
        )
    }

    init(
        screen: NSScreen,
        onIntent: @escaping (IslandIntent) -> Void,
        schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void
    ) {
        self.screen = screen
        self.onIntent = onIntent
        self.schedule = schedule
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    var presentedMode: IslandMode? {
        currentPresentation?.mode
    }

    var latestResultSessionID: SessionID? {
        latestResult?.targetSessionID
    }

    func update(_ snapshot: AppSnapshot) {
        guard let presentation = IslandPresentation.make(
            for: snapshot,
            screenWidth: screen.visibleFrame.width,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            hasLatestResult: latestResult != nil
        ) else {
            hide()
            return
        }
        if let secondary = snapshot.secondaryProcessing.first(where: Self.isCompletedResult),
           let secondaryResult = IslandPresentation.make(
               for: AppSnapshot(
                   status: secondary.status,
                   elapsedMilliseconds: 0,
                   previewText: secondary.previewText,
                   message: secondary.message,
                   organizationPhase: secondary.organizationPhase,
                   organizationRequestID: secondary.organizationRequestID,
                   suggestedRecords: secondary.suggestedRecords
               ),
               screenWidth: screen.visibleFrame.width,
               reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
               targetSessionID: secondary.id
           ) {
            latestResult = secondaryResult
        }
        if presentation.mode == .organized
            || presentation.mode == .localDelivered
            || (presentation.mode == .failed && !presentation.originalText.isEmpty) {
            latestResult = presentation
        }
        show(presentation)
        if let delay = presentation.autoHideDelay {
            scheduleHide(after: delay)
        }
    }

    func hide() {
        scheduleHide(after: 0.25)
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
        let rootView = IslandView(
            presentation: presentation,
            onIntent: onIntent,
            onLocalAction: { [weak self] action in
                self?.handleLocalAction(action)
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

    private func handleLocalAction(_ action: IslandAction) {
        switch action {
        case .dismiss:
            guard currentPresentation?.mode != .idle else { return }
            showIdle()
        case .reopenLatest:
            if let latestResult { show(latestResult) }
        default:
            break
        }
    }

    private func showIdle() {
        guard let idle = IslandPresentation.make(
            for: AppSnapshot(status: .idle, elapsedMilliseconds: 0, previewText: "", message: nil),
            screenWidth: screen.visibleFrame.width,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            hasLatestResult: latestResult != nil
        ) else { return }
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
