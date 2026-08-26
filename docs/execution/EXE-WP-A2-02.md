# EXE-WP-A2-02: Session bundle and clipboard truth

- Plan: [`docs/plans/2026-08-19-wp-a2-02-session-bundle-copy.md`](../plans/2026-08-19-wp-a2-02-session-bundle-copy.md)
- Decision: [`ADR-0004`](../decisions/ADR-0004-alpha2-adaptive-dictation.md)
- Status: passed for bounded `G-A2-DATA`; product acceptance remains in progress
- Branch: `codex/wp-04-alpha2`
- Tested HEAD: `4b7b266`
- Commits: `158bbde`, `4c40c4f`, `1b0d8a9`, `b087eb3`, `8f4b8ed`, `8c47701`, `4b7b266`
- Evidence: [`evidence/WP-A2-02-SESSION-BUNDLE.md`](../../evidence/WP-A2-02-SESSION-BUNDLE.md)
- Started: 2026-08-19
- Finished: 2026-08-19 (technical gate only)

## Delivered scope

New recordings write directly to
`~/Library/Application Support/TSB/Sessions/<UUID>/audio.wav`; the same bundle
receives an atomically written `record.json`. Normal completion, ASR failure and
no-speech outcomes retain the bundle. Explicit recording cancellation removes
only its session directory, while a failed recording start removes its empty
directory. Legacy flat records remain readable and are neither migrated nor
deleted.

The coordinator saves an outcome before publishing a terminal result and copies
only after the success record is durable. Clipboard failure never publishes a
success state. If the pasteboard write succeeds but the delivery-status rewrite
fails, the app reports `已复制，但未能记录复制状态` and does not copy again. The
notch and fallback window derive from the same snapshot: exact successful copy
uses a green native check, accessibility label and 1.2-second display; a
generation token prevents an old hide callback from affecting a newer state.

## Traceability

| WP | ADR | REQ | Production files | Focused tests | AC | Evidence | Commits |
|---|---|---|---|---|---|---|---|
| WP-A2-02 | ADR-0004 | REQ-A2-001, REQ-A2-002 | `Core/Domain/SessionModels.swift`; `Core/Storage/TranscriptStore.swift` | `SessionModelsTests`; `TranscriptStoreTests` | AC-A2-001, AC-A2-002 | `WP-A2-02-SESSION-BUNDLE.md` storage/legacy checks | `158bbde`, `4c40c4f` |
| WP-A2-02 | ADR-0004 | REQ-A2-001, REQ-A2-002, REQ-A2-005 | `Core/Audio/AudioRecordingService.swift`; `App/AppController.swift` | `AudioRecordingServiceTests` | AC-A2-001, AC-A2-002, AC-A2-005 | `WP-A2-02-SESSION-BUNDLE.md` audio lifecycle checks | `1b0d8a9` |
| WP-A2-02 | ADR-0004 | REQ-A2-002, REQ-A2-005, REQ-A2-006 | `Core/Session/SessionCoordinator.swift` | `SessionCoordinatorTests` | AC-A2-002, AC-A2-005, AC-A2-006 | `WP-A2-02-SESSION-BUNDLE.md` outcome/delivery checks | `b087eb3`, `8f4b8ed` |
| WP-A2-02 | ADR-0004 | REQ-A2-006 | `System/Notch/NotchOverlayPanel.swift`; `Views/PlaceholderView.swift` | `OverlayGenerationTests` | AC-A2-006 | `WP-A2-02-SESSION-BUNDLE.md` presentation checks | `8c47701`, `4b7b266` |

Paths in the table are relative to `apps/macos/TSB/TSB` or
`apps/macos/TSB/TSBTests` as applicable.

## Fresh verification

- UI-focused `OverlayGenerationTests`: 4/4 passed.
- Complete macOS App suite: 59/59 passed.
- SenseVoice probe suite: 7/7 passed.
- Paraformer probe suite: 11/11 passed.
- Clean Debug App build: succeeded with code signing disabled.
- `git diff --check` and staged path/content audits: passed before the evidence
  commit; only Markdown evidence/index files were staged.

## Gate and acceptance boundary

`G-A2-DATA` passes as a bounded technical gate: canonical bundle paths,
retained outcomes, exact cancellation, untouched legacy records,
save-before-terminal ordering, truthful clipboard outcomes, accessible 1.2 s
confirmation and stale-callback isolation are automated and reproducible.

`AC-A2-001`, `AC-A2-002`, `AC-A2-005` and `AC-A2-006` remain `in-progress`.
This work package did not perform a real microphone-to-SenseVoice-to-pasteboard
manual smoke. Confirmed history deletion belongs to WP-A2-04, while live device
failure, 10-minute resource release, timing within 100 ms and dual-ASR lifecycle
belong to WP-A2-03/WP-A2-05. No product acceptance criterion is passed here.

## Deviations and risks

- The plan requested the shortest manual audio/copy smoke. It was deliberately
  not claimed because this run was limited to automated evidence; the exact
  remaining procedure is in the evidence file.
- Runtime bundles are private local data and were not opened, copied, hashed or
  staged for this record.
- Xcode reports the existing onnxruntime framework-symlink warning, but both the
  full tests and clean build succeed.

## Rollback

Revert the listed commits in reverse order. Legacy flat records remain in place,
so rollback does not require a data migration. Runtime SessionBundles are outside
Git and must not be removed by repository rollback.
