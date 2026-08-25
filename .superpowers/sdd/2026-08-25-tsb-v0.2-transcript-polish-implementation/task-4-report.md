# Task 4 Report — Lifecycle integration and one-shot delivery

## RED

- Added all eight named lifecycle tests plus storage-backed atomic polish coverage before implementation.
- Command:
  `xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -derivedDataPath /tmp/tsb-polish-task4-red -only-testing:TSBTests/SessionCoordinatorTests -only-testing:TSBTests/TranscriptStoreTests test`
- Expected failure: `Cannot assign to property: 'polish' is a 'let' constant`. The new storage test proved that the existing immutable model could not persist an accepted polish over the already-durable local artifact.
- RED log: `/tmp/tsb-polish-task4-red.log`.

## GREEN

- Command:
  `xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -derivedDataPath /tmp/tsb-polish-task4-final CODE_SIGNING_ALLOWED=NO -only-testing:TSBTests/SessionCoordinatorTests -only-testing:TSBTests/TranscriptStoreTests test`
- Result: 123 tests passed, zero failures: 106 `SessionCoordinatorTests` and 17 `TranscriptStoreTests`.
- GREEN log: `/tmp/tsb-polish-task4-final.log`; result bundle: `/tmp/tsb-polish-task4-final/Logs/Test/Test-TSB-2026.08.25_23-28-43-+0800.xcresult`.

## Lifecycle and race evidence

- Durable local save occurs before either polish or deadline work begins. A manual continuous clock proves Stop at 0 ms, durable local save at 600 ms, accepted polish/copy at 700 ms, and a requested deadline duration of exactly 1,500 ms from the local save.
- Network and deadline use separate task handles. Both callbacks reenter `completeDelivery` on the main actor, recheck shutdown, request identity, lease ownership, and physical `ContinuousClock` time, then reserve the exclusive lease before any polish persistence or clipboard write.
- Accepted path timeline is local save → accepted-polish save → one clipboard write → delivery receipt → organization. A fired deadline after acceptance cannot save or copy again.
- Deadline path copies the durable local text once. A late success cannot persist polish or recopy. A success observed at 1,501 ms loses even when the deadline continuation has not fired.
- Accepted-polish persistence failure stays inside the reserved lease and copies the already-durable local text exactly once.
- Shutdown after the local save leaves that record intact and permits no clipboard write. Cancellation before Stop creates no polish request and no clipboard write.
- Local-only delivery makes no polish or organization request. Organization starts only after delivery, receives the exact `deliveredText`, and never touches the clipboard.
- The test continuations deliberately ignore task cancellation, and deadlines advance via a manual clock rather than wall-clock sleeps, so late-callback and cancellation races are deterministic.

## Implementation

- Reused `Session`, `TranscriptRecord`, `TranscriptStore.save`, and the Task 2/3 polish/settings interfaces; no new service abstraction, dependency, UI, settings model, or network client was introduced.
- Made `TranscriptRecord.polish` mutable so the already-durable record can be atomically rewritten with an accepted/review/failed polish artifact while retaining `localCleanedText`.
- Added local terminology correction before the first save and persists its deterministic edit metadata.
- Persists only the existing non-sensitive polish/delivery receipt fields. No transcript, secret, path, or key logging was added.
- Production dependency wiring remains intentionally deferred to Task 5; Task 4 provides compatibility defaults so existing callers remain source-compatible.

## Self-review / concerns

- `git diff --check` is clean. The focused privacy scan found no task groups, drain pattern, or new logging.
- The default signing invocation is blocked before tests by the existing malformed `onnxruntime.framework` package artifact (`code object is not signed at all`). The source/test build passes with signing disabled, consistent with the prior Task 2/3 reports; no dependency artifact was modified.
- The coordinator retains legacy delivery-status fallback only for existing callers. Task 5 should supply the receipt-aware dependency and live polish client.

## Commit

- `feat(v0.2): deliver polished transcripts with deadline` (current HEAD after commit)

## Fix round 1

### Review findings and RED evidence

- Durable-save deadline anchor: `testDelayedDeadlineTaskStartSleepsOnlyUntilLocalSaveDeadline` failed because the deadline task requested 1,500 ms after already starting 700 ms late, instead of the remaining 800 ms. A second deterministic case covers task start after expiry and proves immediate fallback without invoking the sleeper.
- Timeout and dispatch receipt: the deadline test failed unwrapping a missing `TranscriptPolishRecord`. The post-`willDispatch` failure test likewise failed on a missing record, proving the old error-type check discarded real sent metadata.
- Post-local revoke: the coordinator race test failed to compile because `cancelPendingPolishAfterRevoke` did not exist. The test uses cancellation-insensitive network/deadline continuations and asserts a persisted `.cancelled` artifact, one local copy, and no late save/recopy.
- Stop-to-copy timing: the accepted-path test advanced the continuous clock by 50 ms during accepted-polish persistence and 25 ms during clipboard copy; RED reported 700 ms instead of the required 775 ms.
- RED result directories: `/tmp/tsb-polish-task4-fix1-red`, `/tmp/tsb-polish-task4-fix2-red`, `/tmp/tsb-polish-task4-fix3-red`, `/tmp/tsb-polish-task4-metric-red`, and `/tmp/tsb-polish-task4-postdispatch-red`.

### Fixes

- The deadline task now computes `savedAt + 1.5 seconds` from `localFinalSavedAt`, sleeps only the positive remainder, and enters fallback immediately when task execution begins at or past the physical deadline.
- A dispatched timeout or physically late success best-effort persists `.timedOut` with request/provider/model/kind/count/elapsed metadata before copying durable local text. Pre-dispatch `.notEligible` persists no sent claim; other pre-dispatch failures persist `.failed` with all dispatch fields nil; errors after `willDispatch` retain sent metadata.
- Successful `SettingsModel.revokePolishAccess()` calls an injected default-no-op callback. `TSBAppDelegate` constructs the production model through that callback and `AppController` synchronously enters the coordinator transition. The coordinator invalidates ownership, cancels both handles, reserves the lease, best-effort persists `.cancelled` only when dispatch occurred, and copies local once. Cancellation-insensitive late completions cannot mutate disk or clipboard.
- Network, deadline, and revoke now share the same main-actor `transitionDelivery` lease transition. Organization remains post-delivery and receives the exact delivered text.
- `stopToCopyMilliseconds` samples `continuousNow` only after the clipboard call returns, so accepted persistence and clipboard time are included.

### GREEN and self-review

- Command: `xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -derivedDataPath /tmp/tsb-polish-task4-fixround-final CODE_SIGNING_ALLOWED=NO -only-testing:TSBTests/SessionCoordinatorTests -only-testing:TSBTests/TranscriptStoreTests -only-testing:TSBTests/SettingsBehaviorTests test`.
- Result: 150 tests passed, zero failures: 112 coordinator, 17 storage, and 21 settings/AppDelegate behavior tests.
- `git diff --check` is clean. Focused scan found no task group, drain pattern, or new logging. No consent persistence semantics, dependency package, network client, or UI styling changed.
- Default signing remains blocked by the pre-existing malformed static `onnxruntime.framework`; the focused source/test build passes with signing disabled.
