# WP-01 / AC-SHELL-001 macOS shell evidence

- Date: 2026-08-19
- Device: target M5 Pro Mac, 48GB memory
- Branch: `codex/repo-foundation`
- Tested commit: `7407a28`
- Xcode: 26.6
- XcodeGen: 2.46.0

## Expected

- The generated macOS 14 project builds without signing.
- The initial shell tests pass without recording, ASR, clipboard, cloud or Accessibility behavior.
- Event monitors stop safely, key repeat is idempotent and stale overlay callbacks are rejected.
- OpenDictation adaptations remain attributable to the pinned MIT source.

## Actual

- Project generation completed successfully.
- All 8 XCTest cases passed with 0 failures.
- The unsigned Debug application build succeeded.
- Independent review rejected the first revision for event lifecycle, click-through and license-notice gaps; commit `7407a28` fixed them and the reviewer returned `APPROVED`.
- No interactive visual claim was made.

## Reproduction

```bash
xcodegen generate --spec apps/macos/TSB/project.yml
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## Result

Passed for the non-interactive WP-01 gate. Visual notch and external-display checks remain pending for a later manual gate.
