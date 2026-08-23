# SDD ledger — plan: docs/superpowers/plans/2026-08-20-tsb-v0.2-implementation-plan.md

## Baseline

- Workspace: linked worktree `/Users/zhuohengchi/Desktop/The Second Brain/.worktrees/wp-04-alpha2`
- Branch: `codex/wp-04-alpha2`
- Start commit: `2910f0e`
- Baseline: `xcodebuild ... test` passed 106 tests, 0 failures on 2026-08-20.

## Preflight consistency scan

| Tasks / interface | Producer -> consumer | Finding / ruling |
|---|---|---|
| Task 1 self | models, Codable compatibility, atomic update | Consistent. Model-level tests validate shape; text-dependent reference validation belongs to Task 3. |
| Task 2 self | store listing and local history suggestions | Naming in plan says `SelectedHistory` although the spec requires suggestions that are not automatically sent. Ruling: implement as `HistorySuggestions`; request inclusion remains an explicit selected-ID intersection. Cost if wrong: later call sites need a mechanical rename. |
| Task 3 self | exact text-only OpenAI-compatible request/response boundary | Plan calls the URL a base URL but does not define path inference. Ruling: treat the configured URL as the exact chat-completions endpoint; do not append provider-specific paths. Cost if wrong: users must paste a full endpoint URL rather than a shorter provider base URL. |
| Task 4 self | nonsecret settings and Keychain secret storage | Plan asks Save/Cancel/Delete round-trip although Cancel must not touch persistence. Ruling: Task 4 implements load/save/delete storage; Task 7 owns a draft model whose Cancel reloads persisted values without a store write. Cost if wrong: one small settings draft type is added in Task 7. |
| Task 5 self | coordinator organization axis | Consistent after preflight review: separate capacity, persisted pending, one active request, stale request ID guards. |
| Task 6 self | horizontal interactive island | Consistent. Candidate dimensions are clamped, gestures have visible controls, existing hotkeys remain. |
| Task 7 self | settings-only scene and API form | Ruling from Task 4 applies: user-facing Save/Cancel/Delete are tested here against a draft and the real settings/keychain store. |
| Task 8 self | adversarial fixtures and release evidence | Consistent. JSON fixtures remain Swift literals, avoiding resource-bundle configuration. |
| Tasks 1 -> 2 | `TranscriptRecord.organization` and store -> history summaries | Consistent; Task 2 uses only succeeded numbered points. |
| Tasks 1 -> 3 | organization models -> DTO validation | Consistent; model shape is frozen before network validation. |
| Tasks 1 -> 5 | persisted organization state -> coordinator | Consistent; Task 5 uses Task 1 atomic update and never mutates original/local text. |
| Tasks 1 -> 8 | persisted results -> adversarial acceptance | Consistent. |
| Tasks 2 -> 3 | suggestions/candidate map -> request builder | Consistent with ruling: suggestions do not imply permission; request takes selected-ID allowlist. |
| Tasks 2 -> 5 | local suggestion scan -> organization enrichment | Consistent; automatic current-text organization carries empty history. |
| Tasks 3 -> 4 | endpoint value -> persisted profile | Consistent with exact-endpoint ruling. |
| Tasks 3 -> 5 | client/validator -> coordinator job | Consistent; coordinator freezes request/settings before dispatch. |
| Tasks 4 -> 5 | settings/keychain -> per-dispatch settings closure | Consistent; settings are read per request, then frozen. |
| Tasks 4 -> 7 | persisted profile -> settings UI | Consistent with Save/Cancel/Delete ruling above. |
| Tasks 5 -> 6 | `AppSnapshot`, audio level, intents -> island presentation/actions | Consistent; UI owns no recorder/store/network dependency. |
| Tasks 5 -> 7 | app controller lifetime/settings -> settings scene | Consistent; app delegate owns controller independent of window lifetime. |
| Tasks 6 -> 7 | `AppController`, overlay tests -> settings-only scene | Shared files require sequential implementation; Task 7 must preserve island routing from Task 6. |
| Tasks 5/6 -> 8 | concurrency/UI behavior -> release gates | Consistent; automated checks precede real-mic acceptance. |

## Progress

- Task 1 Ruling (superseded by review): persisted known links store resolved `SessionID`; the remote candidate-ID DTO was initially deferred to Task 3.
- Task 1 implementer: commit `97e3b74`; focused 18/18 and full 113/113 reported passing; review pending.
- Task 1 Ruling: the reviewer is correct that the brief explicitly requires candidate IDs to survive until local resolution — add one request-local candidate-link value plus resolution test while keeping persisted `KnownRecordLink` resolved — cost if wrong: one small type may later be folded into Task 3 DTOs.
- Task 1: fix round 1/5 (2 addressed, 0 open; commits `97e3b74..fc03967`).
- Task 1: complete (commits `2910f0e..fc03967`, review clean).
- Task 2 implementer: commit `dd88907`; focused 16/16 and full 123/123 reported passing; review found three important boundary gaps and one minor diagnostic gap.
- Task 2: fix round 1/5 (4 addressed, 0 open; commits `dd88907..c8533c1`).
- Task 2 minor (deferred): `TranscriptStore.skippedRecordCount` is currently consumed only by tests; final review must decide whether to replace it with an injected diagnostic sink or retain it as product diagnostics.
- Task 2: complete (commits `fc03967..c8533c1`, review clean with 1 deferred minor).
- Task 3 implementer: commit `b05495b`; focused/full suites reported passing; review found two Critical privacy gaps and three Important timeout/schema/correctness gaps.
- Task 3: Fix Round 1 implemented and verified locally; redirect test crash root cause corrected, focused 17/17 and full 143/143 passing, review follow-up pending.
- Task 3: Fix Round 2 strengthened cancellation/timeout evidence with started-request, stop, winner, and late-handler gates; focused 18/18 and full 144/144 passing, review follow-up pending.
- Task 3: Fix Round 3 bounded task-result observation after protocol release; focused 18/18 and full 144/144 passing, review follow-up pending.
- Task 3: Fix Round 4 removed the unretained result watcher and bounded owned-task cleanup; focused 18/18 and full 144/144 passing, review follow-up pending.
