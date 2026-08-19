# EXE-WP-01: Minimal macOS shell

- Plan: `docs/plans/2026-08-19-g0-foundation-and-sensevoice-probe.md`
- Owner: Terra implementation agents, integrated by Sol
- Reviewer: independent Sol and UX reviewers
- Status: passed
- Branch: `codex/repo-foundation`
- Commits: `53d1b97`, `23a02eb`, `0166184`, `7407a28`
- Started: 2026-08-19
- Finished: 2026-08-19

## Files changed

- Added a minimal macOS 14 SwiftUI app and XCTest target under `apps/macos/TSB`.
- Added testable local shortcut deduplication, Escape handling and microphone permission access.
- Selectively adapted the passive notch window, overlay geometry and waveform shell from pinned OpenDictation source.
- Recorded every adapted file and the complete upstream MIT notice in `apps/macos/TSB/UPSTREAM.md`.

## Commands and results

- `xcodegen generate --spec apps/macos/TSB/project.yml`: passed.
- `xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`: 8 tests passed, 0 failures.
- `xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`: passed.
- Both tasks began with an expected compile failure before their production types existed.
- The same generation, 8-test suite and unsigned Debug build passed again after WP-02 was fast-forwarded into `codex/repo-foundation` at `024b8a3`.

## Acceptance criteria and evidence

- Evidence: `evidence/WP-01-AC-SHELL-001-macos-foundation.md`
- App and test Bundle IDs are explicit and do not use an upstream namespace.
- Repeated key-down, key-up reset, stopped-listener behavior, exact modifiers, Escape consumption and stale overlay generations are covered.
- The passive overlay ignores mouse events and does not request Accessibility permission.

## Deviations from plan

- The current event source is local to TSB. Global shortcut registration is deferred to the first complete recording loop, where it can be tested end to end.
- No interactive UI launch was performed, as requested. Notch position and external-display behavior therefore remain manual acceptance items.

## Open risks

- The notch shell has compiled and passed logic tests but has not been visually checked on the target display.
- No recording, ASR, clipboard delivery or application orchestration exists yet.

## Rollback

Revert `7407a28`, `0166184`, `23a02eb` and `53d1b97` in reverse order. The repository foundation is unaffected.
