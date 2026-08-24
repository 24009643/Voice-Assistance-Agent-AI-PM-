# TSB 0.2 Acceptance Matrix

Status values: `passed-automated`, `passed-manual`, `partial-manual`, `pending-manual`, `blocked`, `not-applicable`.

Automated evidence does not pass a manual/device or content-quality gate. TSB 0.2 completion remains **blocked** until every manual row below passes.

## Automated gates

| ID | Requirement | Evidence | Current result | Status |
|---|---|---|---|---|
| V02-A01 | Full macOS app suite | Generated project; `xcodebuild ... test` | 226 passed, 0 failed | passed-automated |
| V02-A02 | Adversarial payloads cross the production parser, validator and client | `OrganizationValidatorTests` + `OrganizationClientTests` | 22 passed, 0 failed | passed-automated |
| V02-A03 | Outbound request is an exact text whitelist | `testSendsOnlyExactEndpointTextSegmentsAndExplicitlySelectedHistory`; exact DTO key assertions and forbidden sentinel scan | Passed in full/focused suites | passed-automated |
| V02-A04 | IDs, hash and category boundaries are objective | Mixed-language valid fixture; unknown candidate/segment, category mixing, malformed JSON and empty-result fixtures | Invalid boundaries rejected; valid/empty contracts accepted | passed-automated |
| V02-A05 | Cancellation/timeout stop the real request and suppress late output | Real `OrganizationClient` path through synthetic `URLProtocol`; controlled no-drain mutation | Mutation failed the timeout regression; restored client passed | passed-automated |
| V02-A06 | Local-only, retry and late organization do not recopy or replace the current session | `SessionCoordinatorTests` | Passed in the 226-test suite | passed-automated |
| V02-A07 | Island sizing, chambers, visible equivalents, stale callbacks and Reduce Motion choices | `IslandPresentationTests`, `IslandFrameTests`, `OverlayGenerationTests` | Passed in the 226-test suite | passed-automated |
| V02-A08 | Consent, selected-history permission and real Save/Cancel/Delete/Revoke semantics | Settings and Keychain test groups | Passed in the 226-test suite | passed-automated |
| V02-A09 | Probe unit boundaries | `swift test --package-path probes/sensevoice`; `swift test --package-path probes/paraformer` | 7/7 and 11/11 passed | passed-automated |
| V02-A10 | Fresh Debug application build | Dedicated empty DerivedData path, code signing disabled | Build succeeded | passed-automated |

## Semantic boundary

Meaning reversal and invented facts are valid JSON that can retain valid IDs, hashes and categories. The current strict schema cannot determine their truth or semantic faithfulness. The adversarial tests preserve those outputs verbatim for review; they do **not** claim automatic detection. Zero meaning reversals, zero invented facts and zero negation changes are therefore Golden Set manual gates.

## Manual and real-product gates

| ID | Required observation | Evidence fields the controller must fill | Status |
|---|---|---|---|
| V02-M01 | Three consecutive real-microphone sessions: Mandarin, Cantonese, Chinese-English mix | Three real session IDs; `record.json` metadata; `audio.wav` sample rate/channels/duration; immediate clipboard equality proof | passed-manual |
| V02-M02 | Organization never changes the clipboard automatically | Immediate post-Stop clipboard equality passed for all three sessions; no configured successful organization cycle was exercised | partial-manual |
| V02-M03 | New recording starts while the previous organization is active | Old/new session IDs, timestamps and island ownership observation | pending-manual |
| V02-M04 | Per-session “仅本地” makes zero remote requests | Session ID plus runtime network observation | pending-manual |
| V02-M05 | Offline, invalid key, timeout and malformed response preserve the local chain | One observation per failure mode, with local record/clipboard outcome and retry availability | pending-manual |
| V02-M06 | Three-chamber result, collapse, reopen and all visible buttons work on the target Mac | Recording and authorization-required island states were captured full-screen; configured three-chamber/collapse/reopen remains missing | partial-manual |
| V02-M07 | Keyboard, VoiceOver and Reduce Motion are usable | Option-Space, Escape, focus/action labels, “推测” announcement and reduced-motion observation | pending-manual |
| V02-M08 | One controlled DeepSeek-compatible call respects the text-only contract | Existing source Keychain item is present, but Keychain authorization rejected secret access with `-25293`; this acceptance attempt issued zero provider requests | blocked |
| V02-M09 | `v0.2-GS-01` has at least 30 real mixed-language records | Paired bundle inventory is 7; GS-qualified and annotated record count is not established | blocked |
| V02-M10 | Local timing and cycle gates meet the design spec | P95/hard-limit results and 100-cycle zero-loss/zero-duplicate-copy summary | blocked |

## Completion decision

`BLOCKED — manual acceptance is incomplete.` V02-M01 passed on the target Mac. V02-M02 and V02-M06 have bounded partial evidence. V02-M08 is blocked by Keychain authorization, V02-M09 lacks a qualified/annotated Golden Set count, and V02-M10 still lacks the 100-cycle/timing run. Do not mark TSB 0.2 complete until every threshold passes.
