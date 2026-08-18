# Upstream provenance

TSB is a new product tree. No upstream source is imported in Task 1.

## OpenDictation reference

- URL: https://github.com/kdcokenny/OpenDictation
- Pinned commit: `227c8b013ba4f4c7d8772b72f062354aae4443b1`
- License: MIT (`LICENSE` at the pinned commit)

## Files considered for later selective porting

- `OpenDictation/Core/Services/HotkeyService.swift`
- `OpenDictation/Core/Services/EscapeKeyMonitor.swift`
- `OpenDictation/Core/Services/PermissionsManager.swift`
- `OpenDictation/Core/Services/KeychainService.swift`
- `OpenDictation/Views/Notch/NSScreen+Notch.swift`
- `OpenDictation/Views/Notch/NotchWindow.swift`
- `OpenDictation/Views/Notch/NotchOverlayPanel.swift`
- `OpenDictation/Views/Notch/NotchShape.swift`
- `OpenDictation/Views/Notch/NotchWaveformView.swift`
- `OpenDictationTests/HotkeyTests.swift`

Any later import must retain this provenance, record local modifications, and exclude OpenDictation cloud ASR, update, history, and text-insertion code.
