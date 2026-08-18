# Upstream provenance

TSB is a new product tree. No upstream source was imported in Task 1.

## OpenDictation reference

- URL: https://github.com/kdcokenny/OpenDictation
- Pinned commit: `227c8b013ba4f4c7d8772b72f062354aae4443b1`
- License: MIT (`LICENSE` at the pinned commit)

## Task 2 selective ports

- `TSB/System/HotkeyService.swift` — adapted from `OpenDictation/Core/Services/HotkeyService.swift`; replaces the `KeyboardShortcuts` dependency with a local AppKit monitor, adds held-key deduplication, and emits only `UserIntent` values.
- `TSB/System/EscapeKeyMonitor.swift` — adapted from `OpenDictation/Core/Services/EscapeKeyMonitor.swift`; replaces the global CGEvent tap with a local AppKit monitor, so no Accessibility permission is requested.
- `TSB/System/MicrophonePermission.swift` — adapted from the microphone-only portion of `OpenDictation/Core/Services/PermissionsManager.swift`; keeps a one-shot AVFoundation request and removes accessibility checks, alerts, settings links, polling, and TCC resets.
- `TSB/System/Notch/NSScreen+Notch.swift` — adapted from `OpenDictation/Views/Notch/NSScreen+Notch.swift`; retains public notch geometry and built-in-screen selection only.
- `TSB/System/Notch/NotchWindow.swift` — adapted from `OpenDictation/Views/Notch/NotchWindow.swift`; retains passive borderless overlay configuration and removes retry/recovery behavior.
- `TSB/System/Notch/NotchOverlayPanel.swift` — adapted from `OpenDictation/Views/Notch/NotchOverlayPanel.swift`; replaces dictation state/view-model integration with a minimal waveform overlay and adds `OverlayGeneration` to ignore stale hide callbacks.
- `TSB/Views/Notch/NotchShape.swift` — adapted from `OpenDictation/Views/Notch/NotchShape.swift`; keeps the notch geometry and removes previews.
- `TSB/Views/Notch/NotchWaveformView.swift` — adapted from `OpenDictation/Views/Notch/NotchWaveformView.swift`; reduces the animated multi-state view to a static four-bar audio-level display.

The ports retain the upstream MIT attribution: Copyright (c) 2025 Kenny. TSB excludes OpenDictation cloud ASR, update, history, text insertion, recording, and accessibility-permission code.
