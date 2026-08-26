# WP-A2-02: Session bundle and clipboard truth evidence

- Tested commit: `4b7b266`
- Date: 2026-08-19, Asia/Shanghai
- Host: Apple silicon `Mac17,8`, arm64, 48 GiB RAM
- OS/toolchain: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), Swift 6.3.3
- Scope: bounded technical `G-A2-DATA` evidence. No private SessionBundle,
  audio, transcript, raw test log or generated Xcode artifact is tracked.

## Automated evidence

| Check | Command | Actual result |
|---|---|---|
| Copy-feedback UI | `xcodebuild ... test -only-testing:TSBTests/OverlayGenerationTests` | 4 tests, 0 failures |
| Full App regression | `xcodebuild ... test` | 59 tests, 0 failures |
| SenseVoice regression | `swift test --package-path probes/sensevoice` | 7 tests, 0 failures |
| Paraformer regression | `swift test --package-path probes/paraformer` | 11 tests, 0 failures |
| Clean App build | `xcodebuild clean build ... CODE_SIGNING_ALLOWED=NO` | clean and build succeeded |
| Repository hygiene | `git diff --check`; staged path, extension and content scans | passed; Markdown evidence/index files only |

The abbreviated Xcode commands use project
`apps/macos/TSB/TSB.xcodeproj`, scheme `TSB`, destination `platform=macOS`
and `CODE_SIGNING_ALLOWED=NO`.

The full suite includes the following WP-specific checks:

- `TranscriptStoreTests` (8): canonical atomic round trip, canonical precedence,
  legacy in-place read/status rewrite, conservative missing legacy metadata,
  delivery-status failure, exact idempotent bundle removal and symlink escape
  rejection.
- `AudioRecordingServiceTests` (7): 16 kHz mono PCM, 600-second limit,
  direct `audio.wav`, completion retention, failed-finish retention, exact
  cancellation, failed-start cleanup and stale recorder isolation.
- `SessionCoordinatorTests` (13): durable save before terminal state, success,
  ASR failure, no speech, save/cleanup/copy/status failures, at-most-once copy,
  Escape cancellation and late audio/ASR callback isolation.
- `OverlayGenerationTests` (4): exact successful message, green native check,
  accessibility label, 1.2-second auto-hide, warning styling and stale callback
  rejection.

## Behavior ruling

| Gate behavior | Evidence | Ruling |
|---|---|---|
| `Sessions/<UUID>/audio.wav` + `record.json` | Recorder/store paths and round-trip tests | passed in technical scope |
| Success/failure/no-speech retention | Recorder and coordinator outcome tests | passed in technical scope |
| Cancellation removes only its bundle | sibling-survival, idempotency and path-escape tests | passed in technical scope |
| Legacy remains readable and untouched | legacy read/rewrite and canonical-precedence tests | passed in technical scope |
| Durable save precedes terminal/copy | coordinator event-order assertions | passed in technical scope |
| Clipboard/UI truth | copy failure and copied/status-write-failed tests | passed in technical scope |
| Accessible green confirmation for 1.2 s | presentation and generation-isolation tests | passed in technical scope |

Therefore `G-A2-DATA` passes only as the technical dependency gate for later
integration. The implementation commits are `158bbde`, `4c40c4f`, `1b0d8a9`,
`b087eb3`, `8f4b8ed`, `8c47701` and `4b7b266`.

## Unclaimed manual/live evidence

No real microphone-to-clipboard smoke was run for this record. The minimum
remaining manual check is:

1. Start one real recording, speak a non-sensitive disposable phrase, then stop.
2. Confirm the green `已复制 · 按 ⌘V 粘贴` state appears and leaves after about
   1.2 seconds; paste once into a disposable local text field.
3. Confirm the matching private bundle contains `audio.wav` and `record.json`
   without adding either file to Git.
4. Repeat once with cancellation and confirm only that active bundle is absent.

This procedure must use disposable content. Its transcript and audio remain
local and are not copied into evidence. Until it and the later live integration
checks are recorded, `AC-A2-001`, `AC-A2-002`, `AC-A2-005` and `AC-A2-006`
remain `in-progress`.

## Repository privacy boundary

`.gitignore` excludes `.superpowers/`, Xcode generated project state, probe
build output, `artifacts/`, `evidence/raw/`, runtime directories, common audio
extensions, model weights, secrets and signing material. The evidence commit
contains no `Sessions/` path, audio file, transcript fixture, model binary or
credential. Runtime data was not inspected for this documentation task.
