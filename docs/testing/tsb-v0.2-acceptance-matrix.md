# TSB 0.2 Acceptance Matrix

Status values: `passed-automated`, `passed-manual`, `partial-manual`, `pending-automated`, `pending-manual`, `blocked`, `not-applicable`.

Automated evidence does not pass a manual/device or content-quality gate. TSB 0.2 completion remains **blocked** until every manual row below passes.

Current source/validation commit: `109e93594299d8808d441ab2bf467263dd378cc5`.

## Automated gates

| ID | Requirement | Evidence | Current result | Status |
|---|---|---|---|---|
| V02-A01 | Full macOS app suite | Exact source commit `109e935` passed the Task 5 full suite; result bundle `/tmp/tsb-v02-recording-runtime-full.xcresult`; diff checks and current/additions count-only scans | 290 passed, 0 failed, 0 skipped | passed-automated |
| V02-A02 | Adversarial payloads cross the production parser, validator and client | `OrganizationValidatorTests` + `OrganizationClientTests` | Passed within the current full and focused suites | passed-automated |
| V02-A03 | Outbound request is an exact text whitelist | `testSendsOnlyExactEndpointTextSegmentsAndExplicitlySelectedHistory`; exact DTO key assertions and forbidden sentinel scan | Passed in full/focused suites | passed-automated |
| V02-A04 | IDs, hash and category boundaries are objective | Mixed-language valid fixture; unknown candidate/segment, category mixing, malformed JSON and empty-result fixtures | Invalid boundaries rejected; valid/empty contracts accepted | passed-automated |
| V02-A05 | Cancellation/timeout stop the real request and suppress late output | Real `OrganizationClient` path through synthetic `URLProtocol`; controlled no-drain mutation | Mutation failed the timeout regression; restored client passed | passed-automated |
| V02-A06 | Local-only, retry and late organization do not recopy or replace the current session | `SessionCoordinatorTests`, including a 100-session structural stress regression | Passed in the current 290-test suite; structural stress is supplemental, not real M10 evidence | passed-automated |
| V02-A07 | Island sizing, chambers, visible equivalents, stale callbacks and Reduce Motion choices | `IslandPresentationTests`, `IslandFrameTests`, `OverlayGenerationTests` | Passed in the current 290-test suite | passed-automated |
| V02-A08 | Consent, selected-history permission and real Save/Cancel/Delete/Revoke semantics | Settings and isolated real-Keychain test groups | Passed in the current 290-test suite | passed-automated |
| V02-A09 | Probe unit boundaries | `swift test --package-path probes/sensevoice`; `swift test --package-path probes/paraformer` | SenseVoice 7/7; Paraformer 11/11; 0 failures | passed-automated |
| V02-A10 | Fresh Debug application build | Prior standalone evidence at `d78f65f`; the Task 5 exact-HEAD gate ran the specified test build only | Not rerun as a standalone Debug-app build at `109e935` | pending-automated |

The Task 5 review-fix commit `109e935` closes six Important and two deferred Minor recording-runtime findings. Its scoped independent re-review is clean. Current/additions count-only scans are zero for provider-token, Bearer, AWS key, GitHub token, PEM private key, private absolute path and `.env` patterns. This is automated evidence only: no merge or release authorization is implied.

## Exact-HEAD recording-runtime gate boundary

The Task 5 full automated gate at exact `109e935` is `passed-automated` only. It does **not** pass the following user-present gates:

| Gate | Current result | Status |
|---|---|---|
| Target-Mac live-preview behavior | Not observed on the target Mac at this exact HEAD | pending-manual |
| Microphone recording/persistence lifecycle | Not exercised through a real microphone at this exact HEAD | pending-manual |
| VoiceOver for the current resident menu/island recovery controls | Not exercised at this exact HEAD | pending-manual |
| V02-M09 Golden Set | 22 paired bundles; no qualified 30-record semantic worksheet | blocked |
| V02-M10 100-cycle timing/stability | Historical run is failed/ineligible; no new authorized run | blocked |
| Merge/release | No user authorization; manual and evidence gates remain | blocked |

## Semantic boundary

Meaning reversal and invented facts are valid JSON that can retain valid IDs, hashes and categories. The current strict schema cannot determine their truth or semantic faithfulness. The adversarial tests preserve those outputs verbatim for review; they do **not** claim automatic detection. Zero meaning reversals, zero invented facts and zero negation changes are therefore Golden Set manual gates.

## Manual and real-product gates

| ID | Required observation | Evidence fields the controller must fill | Status |
|---|---|---|---|
| V02-M01 | Three consecutive real-microphone sessions: Mandarin, Cantonese, Chinese-English mix | Three real session IDs; `record.json` metadata; `audio.wav` sample rate/channels/duration; immediate clipboard equality proof | passed-manual |
| V02-M02 | Organization never changes the clipboard automatically | Adjudicated: three intentionally successful product cycles each had one persisted record, one automatic local copy, immediate clipboard equality and zero organization recopy; failure attempts excluded | passed-manual |
| V02-M03 | New recording starts while the previous organization is active | A second real session started 13.7 seconds after the first while the first `/timeout` request was active; the main island visibly switched to the new recording/local-only state; the first later failed and the second succeeded independently | passed-manual |
| V02-M04 | Per-session “仅本地” makes zero remote requests | Stub `/success` count remained 1→1; local deterministic organization succeeded and clipboard remained equal | passed-manual |
| V02-M05 | Offline, invalid key, timeout and malformed response preserve the local chain | Offline, timeout and malformed-response observations preserved the local record and clipboard. Through the production app/client path, an isolated target-Mac loopback HTTP 401 preserved the copied local record, persisted `organization_failed`, kept clipboard equality and exposed Retry/Copy/Collapse. The design gate is therefore closed without sending a knowingly invalid credential to a live provider; Retry remains an evidence-only target-Mac gap, not a source defect | passed-manual |
| V02-M06 | Three-chamber result, collapse, reopen and all visible buttons work on the target Mac | Configured session `F2844719-3AB6-471F-952D-3D80A9D9F710` showed all three chambers, collapsed to `重新打开最近整理结果`, reopened, and each of the three copy buttons copied the matching chamber; the original clipboard was restored after each check | passed-manual |
| V02-M07 | Keyboard, VoiceOver and Reduce Motion are usable | Historical observation passed for the earlier surface. VoiceOver for the current resident menu/island recovery controls was not exercised at `109e935` | partial-manual |
| V02-M08 | One controlled DeepSeek-compatible call respects the text-only contract | Reused the existing login-Keychain item without displaying, copying, saving, rotating or deleting its secret. Exactly one authorized request used one non-sensitive test segment, no history summaries, and the production `OrganizationClient` → strict DTO decoder → validator chain; it passed | passed-manual |
| V02-M09 | `v0.2-GS-01` has at least 30 real mixed-language records | Metadata-only inventory: 22 paired record/audio bundles; GS-qualified semantic annotations and judgments are not established | blocked |
| V02-M10 | Local timing and cycle gates meet the design spec | Historical single authorized formal run stopped on cycle 1 with `preview_missing` (`100/1` requested/completed, 0 passed rows, 0 loopback/external requests, 0 records, 0 automatic clipboard deliveries, 0 non-loopback observations); consumed run is `failed/ineligible`. Runner prevention is passed-automated in the current 290-test suite; a new attempt requires a validated Paraformer bundle, fresh authorization and exclusive artifacts | blocked |

## Completion decision

`BLOCKED — manual acceptance is incomplete.` Exact `109e935` automated `290/290`, SenseVoice `7/7`, Paraformer `11/11`, clean scoped review and zero current/additions scan counts do not promote target-Mac preview, microphone persistence, current-head VoiceOver, Golden Set, M10, merge or release authorization. V02-M09 remains blocked at 22/30 paired records with no qualified semantic annotations; V02-M10 remains blocked at the failed/ineligible historical `100/1` run.
