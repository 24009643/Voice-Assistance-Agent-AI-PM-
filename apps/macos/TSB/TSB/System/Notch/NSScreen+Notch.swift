import AppKit
import CoreGraphics

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
        screens.first { $0.isBuiltin && $0.hasNotch }
    }
}
