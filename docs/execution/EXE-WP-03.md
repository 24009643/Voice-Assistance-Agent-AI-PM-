# EXE-WP-03: Alpha local dictation chain

- Plan: `docs/plans/2026-08-19-wp-03-alpha-local-chain.md`
- Owner: Sol-coordinated implementation agents
- Reviewer: final non-interactive target-Mac verification
- Status: in-progress — Alpha gate **PENDING / NOT PASSED**
- Branch: `codex/wp-03-evidence`
- Tested main merge: `61c1cb3919d493b9d452354120867a4409fee1ae`
- Started: 2026-08-19
- Evidence collection: 2026-08-19 13:02:24–13:02:48 +0800
- Tag: none; no tag is permitted while the Alpha gate is pending

## Files changed

- Added the Alpha local-chain implementation and its unit/integration tests in earlier WP-03 commits.
- This execution record and `evidence/WP-03-ALPHA-local-chain.md` record verification only; they do not change product behavior.

## Commands and results

- `xcodegen generate --spec apps/macos/TSB/project.yml`: exit 0.
- `xcodebuild clean test -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`: clean succeeded; 44 tests passed, 0 failures, exit 0.
- `swift test --package-path probes/sensevoice`: 7 tests passed, 0 failures, exit 0.
- In `/Users/zhuohengchi/Desktop/The Second Brain/.worktrees/wp-02-g0-run/artifacts/models/sensevoice-2024-07-17-int8`, `shasum -a 256 -c manifest.sha256`: exit 0; `model.int8.onnx`, `tokens.txt` and `LICENSE` all reported `OK`.
- `git diff --check`: exit 0. The evidence worktree was clean after verification.

## Acceptance criteria and evidence

- Evidence: `evidence/WP-03-ALPHA-local-chain.md`
- The frozen-model application was started non-interactively, left running for 17 seconds, reached RSS `1173136 KiB`, did not crash, and left no residual process after termination.
- This is a launch/liveness observation only. It is not evidence that a microphone capture, real ASR, JSON save and clipboard delivery completed.

## Known warnings

- Xcode selected the first of arm64 and x86_64 macOS destinations.
- Xcode reported an onnxruntime XCFramework `Versions/Current` symlink-resolution warning.
- The test-host application reported `linkd.autoShortcut` connection warnings.
- The ASR WAV validation test reported that a non-interleaved audio setting was ignored.

All listed commands still exited 0 and the stated test counts passed. These warnings remain visible for later dependency/toolchain review.

## Alpha gate status

The required human smoke — microphone → real ASR → JSON record → exactly one clipboard write — was **not executed**. Therefore WP-03 Alpha remains **PENDING / NOT PASSED** and must not receive a tag.

## Explicitly out of scope or not implemented

- VAD and stable segmented preview
- Push-to-talk interaction
- Overlapping-session support
- Custom result card UI
- Transcript/audio retention policy
- API profiles and all LLM behavior
- User-consented Golden Set / release-quality validation

## Shortest next-morning manual acceptance

1. Set `TSB_SENSEVOICE_MODEL_DIR` to `/Users/zhuohengchi/Desktop/The Second Brain/.worktrees/wp-02-g0-run/artifacts/models/sensevoice-2024-07-17-int8` and start the Debug app.
2. Grant microphone access, invoke Option-Space, dictate a short Mandarin, Cantonese or mixed Chinese-English phrase, then invoke Option-Space again to stop.
3. Paste once into TextEdit with Command-V. Inspect the session JSON under `~/Library/Application Support/TSB/Sessions/`, and confirm the TSB process opens no external network connection during the run.

Pass only if one interaction creates one saved JSON record with the original transcript preserved, places the delivered text on the clipboard exactly once, the pasted text matches that delivered record, and the app initiates no external network request. If recording, ASR, save, clipboard delivery or the no-network check fails, retain the JSON/audio evidence where present and leave the gate pending.

## Deviations from plan

- The planned final human smoke is deferred to the target user session; no microphone permission prompt or speech was issued during this evidence run.

## Open risks

- Real microphone, ASR, JSON and clipboard handoff has not been observed together on the target machine.
- Runtime privacy/no-external-network behavior has not yet been observed during an end-to-end dictation.
- Cantonese quality remains a release/Golden Set risk documented in WP-02 evidence.
- The noted onnxruntime packaging warning has not been root-caused.

## Rollback

Revert the documentation-only commit that adds this record and its linked evidence. No product behavior is changed by this record.
