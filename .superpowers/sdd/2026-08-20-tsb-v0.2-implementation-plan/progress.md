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
- Task 3: Fix Round 5 drains owned tasks on unreported-stop early exits; focused 19/19 and full 145/145 passing, review follow-up pending.
- Task 3: fix round 5/5 (0 addressed, 1 open — the dedicated unreported-stop regression is a test-of-test and does not drive the shared early-exit guards; commits `70189a1..c01da54`).
- Task 3: parked — dedicated cancellation cleanup regression does not prove the shared early-exit drain — Ruling: the finding is real test-quality debt but does not weaken the reviewed production redirect, timeout, cancellation, hash, ID or strict-schema boundary that Tasks 4–7 consume; carry it into Task 8 and the final whole-branch review, and do not declare v0.2 complete until it is deleted or replaced by a real-path test — cost if wrong: a future cancellation-cleanup regression could escape the focused suite even though current production behavior is unchanged.
- Task 3: complete (commits `c8533c1..c01da54`, 1 parked for mandatory Task 8/final-review resolution).
- Task 4 implementer: commit `a3978af`; focused 9/9 and full 154/154 reported passing; review found two Important Keychain/consent-contract gaps.
- Task 4: fix round 1/5 (3 addressed, 0 open — atomic Keychain replacement, shared request/consent contract, binding test; commits `a3978af..fdb5d45`).
- Task 4: complete (commits `fb75b0b..fdb5d45`, review clean; controller full-suite exit 0 and production credential-pattern scan clean).
- Task 5 implementer: commit `38ece23`; focused 43/43 and full 172/172 reported passing; review found one Critical dispatch-time consent/key mismatch and four Important cancellation, stale-intent, cleanup and persistence gaps.
- Task 5: fix round 1/5 (5 original findings addressed; commit `0663215`; focused 51/51 and full 180/180 reported passing); scoped re-review found one Important first-attempt retry regression and one Minor endpoint/key test-quality gap.
- Task 5: fix round 2/5 (2 addressed, 0 open; commit `b6ee895`; focused 56/56 and full 182/182 reported passing; scoped re-review approved without reopening the original five).
- Task 5: complete (commits `5c127ec..b6ee895`, review clean; controller full suite 182/182 and production credential-pattern scan clean; no live provider request or real key access).
- Task 6 implementer: commit `3394e79`; focused 20/20 and full 192/192 reported passing; review found five Important raw-text, session-routing, latest-result, idle-hit-testing and dynamic-screen gaps plus test-quality minors.
- Task 6: fix round 1/5 (original five production roots substantially addressed; commit `741946c`; focused 83/83 and full 202/202 reported passing); scoped re-review left two Important cleaned-status/screen-reflow gaps and one empty-copy Minor.
- Task 6: fix round 2/5 (two Important addressed; commit `06c3ae0`; focused 87/87 and full 206/206 reported passing); scoped re-review approved with two nonblocking edge/cache Minors.
- Task 6: fix round 3/5 (all remaining Minors addressed, duplicate presentation cache deleted; commit `959b3f9`; focused 23/23 and full 206/206 reported passing; scoped re-review clean).
- Task 6: complete (commits `59056ac..959b3f9`, review clean; controller full suite 206/206, production credential-pattern scan clean; no live provider, real Keychain secret, microphone or external network access).
- Task 7 implementer: commit `dc546f1`; focused 22/22 and full 219/219 reported passing; review found one Important partial-commit mismatch for ordinary remote-to-loopback Save while approving Settings-only lifecycle, BYOK UI and destructive fail-closed semantics.
- Task 7: fix round 1/5 (ordinary noneligible Save made failure-consistent; Revoke/Delete retain explicit fail-closed ordering; commit `c9e6e02`; focused 35/35 and full 221/221 reported passing; scoped re-review clean).
- Task 7: complete (commits `893708a..c9e6e02`, review clean; controller full suite 221/221 and production credential-pattern scan clean; Settings implements real Save/Cancel/Delete/Revoke and never reads a real secret into the UI).
- Task 8 initial automated scope: commit `647aef1`; full TSB 226/226, organization focused 22/22, probes 7/7 and 11/11, fresh Debug build passed; manual/product/Golden Set gates remained open.
- Task 8 target-Mac evidence: commits `ccd77ef`, `7818d7a`, `8bb1caa`; M01/M03/M04/M06 passed, M02/M05/M08 partial, M07 pending, M09/M10 blocked. The latest documentation review was clean and retained the overall `BLOCKED` decision.
- Task 8 continuation baseline: regenerated project at `8bb1caa`; full suite reproduced 226 tests with 17 failures, all in real Keychain-backed settings tests. Focused `KeychainSecretStoreTests` reproduced 2/3 failures with `unexpectedStatus(-25293)`; `security show-keychain-info` returned the same OSStatus.
- Task 8 Ruling: treat the failing baseline as test-environment coupling, not a product bypass — a minimal Security.framework probe created an isolated temporary keychain and added a synthetic generic password with `create=0`, `add=0`; fix tests to target an isolated temporary keychain while production keeps the default login keychain. Cost if wrong: a test-only keychain seam could diverge from default-keychain behavior, so retain real SecItem add/load/update/delete coverage and run a separate product/target-Mac Keychain gate.
- Task 8 Keychain isolation implementer: commit `6272a23`; isolated real Security.framework tests passed 25/25 and full 227/227, but review found one Important missing default-nil query regression.
- Task 8 Keychain isolation fix round 1/5 (1 addressed, 0 open; commit `1bd77ad`; mutation RED 0/1, restored Keychain 5/5, required groups 26/26 and full 228/228; scoped re-review approved with no new Critical/Important findings).
- Task 8 Keychain isolation slice complete (commits `8bb1caa..1bd77ad`, review clean; production default login-Keychain construction remains unchanged and the separate target-Mac product Keychain gate remains open).
- Task 8 M10 runner implementer: commit `3bebe6d`; structural duplicate-copy mutation RED 0/1 then restored 1/1, runner 5/5, focused 81/81, full 234/234 and Debug build reported passing; review found one Critical delayed-permission recording risk, two Important output-overwrite/unbounded-cycle risks and one Minor negative-gate coverage gap.
- Task 8 M10 fix round 1/5 (4 addressed, 0 open; commit `3c5e62a`; runner covering 9/9, focused 85/85, full 238/238, Debug build and static scans passed; validator independently confirmed frozen result bundles/current HEAD and ran a clean Debug build; scoped re-review approved with no new Critical/Important findings).
- Task 8 M10 Ruling: cycle counts `1...99` are valid rehearsals that emit `m10_ineligible`, `100` is the only formal M10 input, and `>100` is invalid and rejected before any file/audio/record/clipboard side effect — this follows the product spec and the original review's explicit direct-rejection option; cost if wrong: an operator typo above 100 gets no JSON diagnostic and must correct the runtime input.
- Task 8 M10 runner slice: `implemented`, `review-clean`, `passed-automated` (commits `1bd77ad..3c5e62a`); V02-M10 remains `blocked` because the user-authorized target-Mac exactly-100-cycle run has not occurred.
- Task 8 V02-M05 evidence adjudication: existing production-app loopback HTTP 401 evidence closes the authentication-failure gate as `passed-manual`; no knowingly invalid live-provider credential was sent. M02, M07, M08, M09 and M10, all other gate states, and the overall `BLOCKED` release decision remain unchanged.
