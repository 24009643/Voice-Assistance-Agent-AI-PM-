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
