import AppKit
import CoreGraphics

struct IslandFrame {
    static let screenMargin: CGFloat = 12
    static let fallbackTopInset: CGFloat = 12

    static func make(
        preferredSize: CGSize,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        hardwareNotchFrame: CGRect?
    ) -> CGRect {
        let width = min(preferredSize.width, max(1, visibleFrame.width - screenMargin * 2))
        let height = min(preferredSize.height, max(1, visibleFrame.height - screenMargin * 2))
        let centerX = hardwareNotchFrame?.midX ?? visibleFrame.midX
        let minX = visibleFrame.minX + screenMargin
        let maxX = visibleFrame.maxX - screenMargin - width
        let x = min(max(centerX - width / 2, minX), maxX)
        let top = hardwareNotchFrame == nil
            ? visibleFrame.maxY - fallbackTopInset
            : screenFrame.maxY
        return CGRect(x: x, y: top - height, width: width, height: height)
    }
}

/// Adapted from OpenDictation/Views/Notch/NSScreen+Notch.swift (MIT, Copyright (c) 2025 Kenny).
extension NSScreen {
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea?.width,
              let right = auxiliaryTopRightArea?.width,
              left > 0,
              right > 0 else { return .zero }

        return CGSize(width: frame.width - left - right, height: safeAreaInsets.top + 0.25)
    }

    var hasNotch: Bool {
        notchSize != .zero
    }

    var notchFrame: CGRect {
        guard hasNotch, let left = auxiliaryTopLeftArea?.width else { return .zero }
        return CGRect(
            x: frame.minX + left,
            y: frame.maxY - safeAreaInsets.top,
            width: notchSize.width,
            height: notchSize.height
        )
    }

    var isBuiltin: Bool {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = deviceDescription[key] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(number.uint32Value) != 0
    }

    static func findScreenForNotch() -> NSScreen? {
        screens.first { $0.isBuiltin && $0.hasNotch } ?? main ?? screens.first
    }

    func islandFrame(for preferredSize: CGSize) -> CGRect {
        IslandFrame.make(
            preferredSize: preferredSize,
            screenFrame: frame,
            visibleFrame: visibleFrame,
            hardwareNotchFrame: isBuiltin && hasNotch ? notchFrame : nil
        )
    }
}
