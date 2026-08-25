# TSB 0.2 Acceptance Matrix

Status values: `passed-automated`, `passed-manual`, `partial-manual`, `pending-automated`, `pending-manual`, `blocked`, `not-applicable`.

Automated evidence does not pass a manual/device or content-quality gate. TSB 0.2 completion remains **blocked** until every manual row below passes.

Current implementation commit: `12139cb0609da2f87ad6e89050bbddb4e9b8064e`. Lifecycle-correction review-record commit and exact post-review gate HEAD: `2cde5265ebde9bb856a0d7b52d2a704c9676c56f`.

## Automated gates

| ID | Requirement | Evidence | Current result | Status |
|---|---|---|---|---|
| V02-A01 | Full macOS app suite | Exact post-review gate HEAD `2cde526` includes the lifecycle-correction review-record commit; result bundle `/tmp/tsb-v02-lifecycle-correction.xcresult`; diff checks and current/additions count-only scans | 318 passed, 0 failed, 0 skipped | passed-automated |
| V02-A02 | Adversarial payloads cross the production parser, validator and client | `OrganizationValidatorTests` + `OrganizationClientTests` | Passed within the current full and focused suites | passed-automated |
| V02-A03 | Outbound request is an exact text whitelist | `testSendsOnlyExactEndpointTextSegmentsAndExplicitlySelectedHistory`; exact DTO key assertions and forbidden sentinel scan | Passed in full/focused suites | passed-automated |
| V02-A04 | IDs, hash and category boundaries are objective | Mixed-language valid fixture; unknown candidate/segment, category mixing, malformed JSON and empty-result fixtures | Invalid boundaries rejected; valid/empty contracts accepted | passed-automated |
| V02-A05 | Cancellation/timeout stop the real request and suppress late output | Real `OrganizationClient` path through synthetic `URLProtocol`; controlled no-drain mutation | Mutation failed the timeout regression; restored client passed | passed-automated |
| V02-A06 | Local-only, retry and late organization do not recopy or replace the current session | `SessionCoordinatorTests`, including a 100-session structural stress regression | Passed in the current 318-test suite; structural stress is supplemental, not real M10 evidence | passed-automated |
| V02-A07 | Island sizing, chambers, visible equivalents, stale callbacks and Reduce Motion choices | `IslandPresentationTests`, `IslandFrameTests`, `OverlayGenerationTests` | Passed in the current 318-test suite | passed-automated |
| V02-A08 | Consent, selected-history permission and real Save/Cancel/Delete/Revoke semantics | Settings and isolated real-Keychain test groups | Passed in the current 318-test suite | passed-automated |
| V02-A09 | Probe unit boundaries | `swift test --package-path probes/sensevoice`; `swift test --package-path probes/paraformer` | SenseVoice 7/7; Paraformer 11/11; 0 failures | passed-automated |
| V02-A10 | Fresh Debug application build | Exact post-review build at `2cde526`; derived data `/tmp/tsb-v02-lifecycle-correction-build` | Unsigned Debug `TSB.app` built successfully | passed-automated |

The lifecycle-correction implementation through `12139cb` separates destructive active-capture cancellation from Stop preservation, shutdown/task cleanup, callback handoff and Debug cleanup; it also closes controller task ownership and privacy-receipt propagation. The independent whole-range review is preserved in tracked commit `2cde526` and was committed before the fresh post-review gate. Current/additions count-only scans across 12 changed files are zero for provider-token, Bearer, AWS key, GitHub token, PEM private key, private absolute path and `.env` patterns. This is automated evidence only: no merge or release authorization is implied.

## Transcript-polish Task 6 evidence (`323d7bb`)

| ID | Requirement | Evidence | Current result | Status |
|---|---|---|---|---|
| V02-P01 | Transcript-polish focused aggregate | Normal invocation reached the existing signing artifact; rerun with `CODE_SIGNING_ALLOWED=NO` selected `TranscriptTerminology`, polish model/validator/client, settings, coordinator, store and acceptance-runner groups | **208/208 passed, 0 failed, 0 skipped** | passed-automated |
| V02-P02 | Fresh full macOS app suite | Normal run wrote `/tmp/tsb-polish-full.xcresult` but stopped during app signing. Signing-disabled run wrote `/tmp/tsb-polish-full-unsigned.xcresult` and was interrupted after stalling in `SettingsSourceTests.testAPIKeyUsesNonLoginContentTypeAndModelIsNotACredentialField`; no final suite count exists | No full-suite pass result | blocked |
| V02-P03 | Fresh Debug build | Normal build stopped during `CodeSign TSB.app`: `code object is not signed at all`, subcomponent `onnxruntime.framework`; separate `CODE_SIGNING_ALLOWED=NO` build at `/tmp/tsb-polish-build-unsigned` completed | Unsigned Debug build succeeded; signed Debug build remains blocked by the copied framework artifact | passed-automated (unsigned only) |
| V02-P04 | Range hygiene and bounded privacy scan | `git diff --check eba721b..323d7bb` was clean; pre-documentation `git status --short` was empty. Added production lines: 0 credential signatures, 0 Bearer value literals, 0 private absolute paths, 0 logging calls; one coordinator delivery copy call and 0 direct `clipboard.copy` additions | Static scan clean within the stated patterns | passed-automated |

The request constructor sends only `schema_version`, `request_id`, candidate `candidate_id`/`text`/`text_sha256`, and approved terminology; the changed current code has no audio, path, history, clipboard, record, or session-ID request field. This bounded static scan and focused test evidence do not prove a real Provider request, real clipboard/disk state, or absence of every possible sensitive-data path.

### Transcript-polish manual boundary

| Gate | Current result | Status |
|---|---|---|
| Real mixed Chinese-English microphone quality and durable recording evidence | Not performed in Task 6 | pending-manual |
| One authorized real Provider polish request and measured latency | Not performed in Task 6 | pending-manual |
| Target-Mac Stop-to-copy timing and immediate clipboard/disk equality | Not performed in Task 6 | pending-manual |
| Figma/SwiftUI visual and accessibility acceptance | Not performed in Task 6 | pending-manual |
| Mixed-language Golden Set and M10 | Not performed in Task 6; existing matrix blockers remain | blocked |

Task 6 does not make a release, merge, push, or manual-acceptance claim. The incomplete full suite and the normal signed-build artifact remain release blockers.

## Exact-HEAD lifecycle-correction gate boundary

The lifecycle-correction post-review automated gate at exact `2cde526` is `passed-automated` only. It does **not** pass the following user-present gates:

| Gate | Current result | Status |
|---|---|---|
| Target-Mac live-preview behavior | Not observed on the target Mac at `2cde526` | pending-manual |
| Microphone recording/persistence lifecycle | Not exercised through a real microphone at `2cde526` | pending-manual |
| VoiceOver for the current resident menu/island recovery controls | Not exercised at `2cde526` | pending-manual |
| V02-M09 Golden Set | 22 paired bundles; no qualified 30-record semantic worksheet | blocked |
| V02-M10 100-cycle timing/stability | Historical run is failed/ineligible; no new authorized run | blocked |
| Reachable-history owner disposition | Historical reachable-history diagnostics still require explicit owner disposition | blocked |
| Merge/push/release | No user authorization; manual and evidence gates remain | blocked |

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
| V02-M07 | Keyboard, VoiceOver and Reduce Motion are usable | Historical broader-surface observation is `partial-manual`. VoiceOver for the current resident menu/island recovery controls was not exercised at `2cde526` | pending-manual |
| V02-M08 | One controlled DeepSeek-compatible call respects the text-only contract | Reused the existing login-Keychain item without displaying, copying, saving, rotating or deleting its secret. Exactly one authorized request used one non-sensitive test segment, no history summaries, and the production `OrganizationClient` → strict DTO decoder → validator chain; it passed | passed-manual |
| V02-M09 | `v0.2-GS-01` has at least 30 real mixed-language records | Metadata-only inventory: 22 paired record/audio bundles; GS-qualified semantic annotations and judgments are not established | blocked |
| V02-M10 | Local timing and cycle gates meet the design spec | Historical single authorized formal run stopped on cycle 1 with `preview_missing` (`100/1` requested/completed, 0 passed rows, 0 loopback/external requests, 0 records, 0 automatic clipboard deliveries, 0 non-loopback observations); consumed run is `failed/ineligible`. Runner prevention is passed-automated in the current 318-test suite; a new attempt requires target-Mac validation of the installed Paraformer bundle, fresh authorization and exclusive artifacts | blocked |

## Completion decision

`BLOCKED — manual acceptance is incomplete.` Exact post-review `2cde526` automated `318/318`, standalone Debug build, SenseVoice `7/7`, Paraformer `11/11`, tracked clean whole-correction review and zero current/additions scan counts do not promote target-Mac preview, microphone persistence, current resident-controls VoiceOver, Golden Set, M10, reachable-history owner disposition, merge or release authorization. Current resident-controls VoiceOver is `pending-manual`; historical broader M07 remains `partial-manual`. V02-M09 remains blocked at 22/30 paired records with no qualified semantic annotations; V02-M10 remains blocked at the failed/ineligible historical `100/1` run pending target-Mac validation of the installed Paraformer bundle and fresh authorization.
