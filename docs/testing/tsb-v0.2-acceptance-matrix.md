# TSB 0.2 Acceptance Matrix

Status values: `passed-automated`, `passed-manual`, `partial-manual`, `pending-manual`, `blocked`, `not-applicable`.

Automated evidence does not pass a manual/device or content-quality gate. TSB 0.2 completion remains **blocked** until every manual row below passes.

Current product/fix/validation commit: `98341b36246ae7c5dcc0406bf8a7f088bc7f6183`.

## Automated gates

| ID | Requirement | Evidence | Current result | Status |
|---|---|---|---|---|
| V02-A01 | Full macOS app suite | Exact-HEAD `98341b3` independently passed focused `27/27`, full suite `249/249`, fresh Debug build, diff/project consistency, sensitive scan and cleanup | 249 passed, 0 failed, 0 skipped | passed-automated |
| V02-A02 | Adversarial payloads cross the production parser, validator and client | `OrganizationValidatorTests` + `OrganizationClientTests` | 22 passed, 0 failed | passed-automated |
| V02-A03 | Outbound request is an exact text whitelist | `testSendsOnlyExactEndpointTextSegmentsAndExplicitlySelectedHistory`; exact DTO key assertions and forbidden sentinel scan | Passed in full/focused suites | passed-automated |
| V02-A04 | IDs, hash and category boundaries are objective | Mixed-language valid fixture; unknown candidate/segment, category mixing, malformed JSON and empty-result fixtures | Invalid boundaries rejected; valid/empty contracts accepted | passed-automated |
| V02-A05 | Cancellation/timeout stop the real request and suppress late output | Real `OrganizationClient` path through synthetic `URLProtocol`; controlled no-drain mutation | Mutation failed the timeout regression; restored client passed | passed-automated |
| V02-A06 | Local-only, retry and late organization do not recopy or replace the current session | `SessionCoordinatorTests`, including a 100-session structural stress regression | Passed in the 249-test suite; structural stress is supplemental, not real M10 evidence | passed-automated |
| V02-A07 | Island sizing, chambers, visible equivalents, stale callbacks and Reduce Motion choices | `IslandPresentationTests`, `IslandFrameTests`, `OverlayGenerationTests` | Passed in the 249-test suite | passed-automated |
| V02-A08 | Consent, selected-history permission and real Save/Cancel/Delete/Revoke semantics | Settings and isolated real-Keychain test groups | Passed in the 249-test suite | passed-automated |
| V02-A09 | Probe unit boundaries | `swift test --package-path probes/sensevoice`; `swift test --package-path probes/paraformer` | 7/7 and 11/11 passed | passed-automated |
| V02-A10 | Fresh Debug application build | Exact-HEAD offline clean snapshot, dedicated DerivedData path, code signing disabled | Build succeeded | passed-automated |

## Semantic boundary

Meaning reversal and invented facts are valid JSON that can retain valid IDs, hashes and categories. The current strict schema cannot determine their truth or semantic faithfulness. The adversarial tests preserve those outputs verbatim for review; they do **not** claim automatic detection. Zero meaning reversals, zero invented facts and zero negation changes are therefore Golden Set manual gates.

## Manual and real-product gates

| ID | Required observation | Evidence fields the controller must fill | Status |
|---|---|---|---|
| V02-M01 | Three consecutive real-microphone sessions: Mandarin, Cantonese, Chinese-English mix | Three real session IDs; `record.json` metadata; `audio.wav` sample rate/channels/duration; immediate clipboard equality proof | passed-manual |
| V02-M02 | Organization never changes the clipboard automatically | Adjudicated: three intentionally successful product cycles each had one persisted record, one automatic local copy, immediate clipboard equality and zero organization recopy; failure attempts excluded | passed-manual |
| V02-M03 | New recording starts while the previous organization is active | A second real session started 13.7 seconds after the first while the first `/timeout` request was active; the main island visibly switched to the new recording/local-only state; the first later failed and the second succeeded independently | passed-manual |
| V02-M04 | Per-session “仅本地” makes zero remote requests | Stub `/success` count remained 1→1; local deterministic organization succeeded and clipboard remained equal | passed-manual |
| V02-M05 | Offline, invalid key, timeout and malformed response preserve the local chain | Offline, timeout and malformed-response observations preserved the local record and clipboard. Through the production app/client path, an isolated target-Mac loopback HTTP 401 preserved the copied local record, persisted `organization_failed`, kept clipboard equality and exposed Retry/Copy/Collapse. The design gate is therefore closed without sending a knowingly invalid credential to a live provider | passed-manual |
| V02-M06 | Three-chamber result, collapse, reopen and all visible buttons work on the target Mac | Configured session `F2844719-3AB6-471F-952D-3D80A9D9F710` showed all three chambers, collapsed to `重新打开最近整理结果`, reopened, and each of the three copy buttons copied the matching chamber; the original clipboard was restored after each check | passed-manual |
| V02-M07 | Keyboard, VoiceOver and Reduce Motion are usable | Physical Option-Space then Escape cancellation and automatic island collapse passed from the user's retest (`也已经自动收齐了`). VoiceOver focus/action/“推测” announcement and Reduce Motion island/waveform observations remain pending | partial-manual |
| V02-M08 | One controlled DeepSeek-compatible call respects the text-only contract | Immediately before authorized runtime work, Settings showed loopback `127.0.0.1:63060`, model `local-acceptance`, API Key `未保存`, cloud consent `未授权`, selected-history off/disabled; the authorized DeepSeek request was not started and Provider count was `0`. No Keychain secret was touched; a user must save a key before a later product-path attempt | blocked |
| V02-M09 | `v0.2-GS-01` has at least 30 real mixed-language records | Paired bundle inventory is 17; GS-qualified and annotated record count is not established | blocked |
| V02-M10 | Local timing and cycle gates meet the design spec | Single authorized formal run stopped on cycle 1 with `preview_missing` (`100/1` requested/completed, 0 passed rows, 0 loopback/external requests, 0 records, 0 automatic clipboard deliveries, 0 non-loopback observations); consumed run is `failed/ineligible`. Absent Paraformer environment caused the intentional no-op preview pipeline. Runner-only prevention is review-clean/passed-automated; exact-HEAD validation is `249/249`. A new attempt requires validated Paraformer, fresh authorization and exclusive artifacts | blocked |

## Completion decision

`BLOCKED — manual acceptance is incomplete.` V02-M01, M03, M04, M05, M06 and adjudicated M02 are passed; V02-M07 is `partial-manual` because physical Option-Space/Escape cancellation and automatic collapse passed while VoiceOver and Reduce Motion remain pending; V02-M08, M09 and M10 are blocked. The historical Critical runner incident remains open as an incident record (`3 vs 1` Provider requests, `5 vs 3` records, `5 vs 3` automatic copies). Task 7 Model-field integrity is passed only for its focused subgate; V02-M08 and release completion remain blocked. The current product/fix/validation commit `98341b3` automated `249/249` result and Debug build do not promote Provider, accessibility, Golden Set, stability or release gates.
