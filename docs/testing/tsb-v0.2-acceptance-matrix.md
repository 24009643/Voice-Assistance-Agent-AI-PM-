# TSB 0.2 Acceptance Matrix

Status values: `passed-automated`, `passed-manual`, `partial-manual`, `pending-manual`, `blocked`, `not-applicable`.

Automated evidence does not pass a manual/device or content-quality gate. TSB 0.2 completion remains **blocked** until every manual row below passes.

## Automated gates

| ID | Requirement | Evidence | Current result | Status |
|---|---|---|---|---|
| V02-A01 | Full macOS app suite | Generated project; frozen HEAD `3c5e62a` result bundle independently checked | 238 passed, 0 failed, 0 skipped | passed-automated |
| V02-A02 | Adversarial payloads cross the production parser, validator and client | `OrganizationValidatorTests` + `OrganizationClientTests` | 22 passed, 0 failed | passed-automated |
| V02-A03 | Outbound request is an exact text whitelist | `testSendsOnlyExactEndpointTextSegmentsAndExplicitlySelectedHistory`; exact DTO key assertions and forbidden sentinel scan | Passed in full/focused suites | passed-automated |
| V02-A04 | IDs, hash and category boundaries are objective | Mixed-language valid fixture; unknown candidate/segment, category mixing, malformed JSON and empty-result fixtures | Invalid boundaries rejected; valid/empty contracts accepted | passed-automated |
| V02-A05 | Cancellation/timeout stop the real request and suppress late output | Real `OrganizationClient` path through synthetic `URLProtocol`; controlled no-drain mutation | Mutation failed the timeout regression; restored client passed | passed-automated |
| V02-A06 | Local-only, retry and late organization do not recopy or replace the current session | `SessionCoordinatorTests`, including a 100-session structural stress regression | Passed in the 238-test suite; structural stress is supplemental, not real M10 evidence | passed-automated |
| V02-A07 | Island sizing, chambers, visible equivalents, stale callbacks and Reduce Motion choices | `IslandPresentationTests`, `IslandFrameTests`, `OverlayGenerationTests` | Passed in the 238-test suite | passed-automated |
| V02-A08 | Consent, selected-history permission and real Save/Cancel/Delete/Revoke semantics | Settings and isolated real-Keychain test groups | Passed in the 238-test suite | passed-automated |
| V02-A09 | Probe unit boundaries | `swift test --package-path probes/sensevoice`; `swift test --package-path probes/paraformer` | 7/7 and 11/11 passed | passed-automated |
| V02-A10 | Fresh Debug application build | Dedicated empty DerivedData path, code signing disabled | Build succeeded | passed-automated |

## Semantic boundary

Meaning reversal and invented facts are valid JSON that can retain valid IDs, hashes and categories. The current strict schema cannot determine their truth or semantic faithfulness. The adversarial tests preserve those outputs verbatim for review; they do **not** claim automatic detection. Zero meaning reversals, zero invented facts and zero negation changes are therefore Golden Set manual gates.

## Manual and real-product gates

| ID | Required observation | Evidence fields the controller must fill | Status |
|---|---|---|---|
| V02-M01 | Three consecutive real-microphone sessions: Mandarin, Cantonese, Chinese-English mix | Three real session IDs; `record.json` metadata; `audio.wav` sample rate/channels/duration; immediate clipboard equality proof | passed-manual |
| V02-M02 | Organization never changes the clipboard automatically | Immediate equality passed for three real-microphone sessions; one configured successful organization and local-only organization also retained clipboard equality | partial-manual |
| V02-M03 | New recording starts while the previous organization is active | A second real session started 13.7 seconds after the first while the first `/timeout` request was active; the main island visibly switched to the new recording/local-only state; the first later failed and the second succeeded independently | passed-manual |
| V02-M04 | Per-session “仅本地” makes zero remote requests | Stub `/success` count remained 1→1; local deterministic organization succeeded and clipboard remained equal | passed-manual |
| V02-M05 | Offline, invalid key, timeout and malformed response preserve the local chain | Offline, timeout and malformed-response observations preserved the local record and clipboard. Through the production app/client path, an isolated target-Mac loopback HTTP 401 preserved the copied local record, persisted `organization_failed`, kept clipboard equality and exposed Retry/Copy/Collapse. The design gate is therefore closed without sending a knowingly invalid credential to a live provider | passed-manual |
| V02-M06 | Three-chamber result, collapse, reopen and all visible buttons work on the target Mac | Configured session `F2844719-3AB6-471F-952D-3D80A9D9F710` showed all three chambers, collapsed to `重新打开最近整理结果`, reopened, and each of the three copy buttons copied the matching chamber; the original clipboard was restored after each check | passed-manual |
| V02-M07 | Keyboard, VoiceOver and Reduce Motion are usable | Option-Space, Escape, focus/action labels, “推测” announcement and reduced-motion observation | pending-manual |
| V02-M08 | One controlled DeepSeek-compatible call respects the text-only contract | Exactly one direct provider smoke used synthetic mixed-language text only with `deepseek-v4-flash`; HTTP 200 returned the requested smoke-test JSON, 186 prompt + 174 completion tokens. No audio, path, history, transcript or memory-library content was sent, and the temporary credential reference was unset. The call did not run through the production `OrganizationClient` parser/validator contract | partial-manual |
| V02-M09 | `v0.2-GS-01` has at least 30 real mixed-language records | Paired bundle inventory is 17; GS-qualified and annotated record count is not established | blocked |
| V02-M10 | Local timing and cycle gates meet the design spec | DEBUG runner is implemented and review-clean; automated 100-session structural stress passed. No target-Mac exactly-100-cycle P95/hard-limit/zero-loss summary has been run | blocked |

## Completion decision

`BLOCKED — manual acceptance is incomplete.` V02-M01, M03, M04, M05 and M06 passed on the target Mac. V02-M02 and M08 have bounded partial evidence, V02-M07 remains pending, V02-M09 lacks a qualified/annotated Golden Set count, and V02-M10 still lacks the 100-cycle/timing run. Do not mark TSB 0.2 complete until every threshold passes.
