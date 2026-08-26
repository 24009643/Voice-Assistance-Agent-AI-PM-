# TSB 0.2 Acceptance Matrix

Status values: `passed-automated`, `passed-manual`, `partial-manual`, `pending-automated`, `pending-manual`, `blocked`, `not-applicable`.

Automated evidence does not pass a manual/device or content-quality gate. TSB 0.2 completion remains **blocked** until every manual row below passes.

Current product implementation commit: `882aec258ad3d1111d210ba11f6a1a740c535fc3`; current acceptance correction and gate HEAD: `817328e5d5aa5487e11ed611fc825a301bde2e04`. The current unsigned full-suite gate is **394/394 passed, 0 failed, 0 skipped**. Lifecycle-correction review-record commit and historical exact post-review gate HEAD: `2cde5265ebde9bb856a0d7b52d2a704c9676c56f`.

## Automated gates

| ID | Requirement | Evidence | Current result | Status |
|---|---|---|---|---|
| V02-A01 | Full macOS app suite | Exact post-review gate HEAD `2cde526` includes the lifecycle-correction review-record commit; result bundle `/tmp/tsb-v02-lifecycle-correction.xcresult`; diff checks and current/additions count-only scans | 318 passed, 0 failed, 0 skipped | passed-automated |
| V02-A02 | Adversarial payloads cross the production parser, validator and client | `OrganizationValidatorTests` + `OrganizationClientTests` | Passed within the historical exact-head 318-test suite and focused suites | passed-automated |
| V02-A03 | Outbound request is an exact text whitelist | `testSendsOnlyExactEndpointTextSegmentsAndExplicitlySelectedHistory`; exact DTO key assertions and forbidden sentinel scan | Passed in full/focused suites | passed-automated |
| V02-A04 | IDs, hash and category boundaries are objective | Mixed-language valid fixture; unknown candidate/segment, category mixing, malformed JSON and empty-result fixtures | Invalid boundaries rejected; valid/empty contracts accepted | passed-automated |
| V02-A05 | Cancellation/timeout stop the real request and suppress late output | Real `OrganizationClient` path through synthetic `URLProtocol`; controlled no-drain mutation | Mutation failed the timeout regression; restored client passed | passed-automated |
| V02-A06 | Local-only, retry and late organization do not recopy or replace the current session | `SessionCoordinatorTests`, including a 100-session structural stress regression | Passed in the historical exact-head 318-test suite; structural stress is supplemental, not real M10 evidence | passed-automated |
| V02-A07 | Island sizing, chambers, visible equivalents, stale callbacks and Reduce Motion choices | `IslandPresentationTests`, `IslandFrameTests`, `OverlayGenerationTests` | Passed in the historical exact-head 318-test suite | passed-automated |
| V02-A08 | Consent, selected-history permission and real Save/Cancel/Delete/Revoke semantics | Settings and isolated real-Keychain test groups | Passed in the historical exact-head 318-test suite | passed-automated |
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

At the original Task 6 boundary, the full suite was incomplete and the normal signed-build artifact remained blocked. Later final re-review evidence below supersedes only the unsigned full-suite result; it does not make a release, merge, push, signed-build, or manual-acceptance claim.

## Transcript-polish final-fix evidence (post-`1358a47`)

| ID | Requirement | Evidence | Current result | Status |
|---|---|---|---|---|
| V02-P05 | Final blocking-fix affected aggregate | Fresh `CODE_SIGNING_ALLOWED=NO` run selected terminology, polish model/validator/client, settings, coordinator, store, and acceptance-runner groups; `/tmp/tsb-final-fixes-focused-final.xcresult` | **218/218 passed, 0 failed, 0 skipped** | passed-automated |
| V02-P06 | Final blocking-fix Debug build | Fresh `CODE_SIGNING_ALLOWED=NO` Debug build at `/tmp/tsb-final-fixes-build-final` | Unsigned Debug build succeeded | passed-automated (unsigned only) |
| V02-P07 | Full-suite source-bundle hypothesis | The exact five inspected `.swift` sources were temporarily configured as `TSBTests` resources and the project regenerated. The isolated named test completed, but Xcode reported that the Swift files cannot be processed by Copy Bundle Resources and bundle lookup returned nil. The experiment was reverted as required; no alternative was attempted | No full-suite pass or new full-suite count | blocked |
| V02-P08 | Final-fix hygiene and bounded privacy scan | `git diff --check` clean; no final `project.yml`/generated-project resource-experiment diff. Added production lines from `1358a47`: 0 provider-token signatures, Bearer values, PEM private keys, private `/Users/` paths, `.env` references, logging calls, or clipboard calls | Static scan clean within the stated patterns | passed-automated |

These final-fix results do not change the manual boundary. Normal signed test/build remains unproven and blocked on the copied `onnxruntime.framework` artifact; real Provider, microphone, target-Mac timing, clipboard/disk, Figma/SwiftUI, Golden Set, M10, merge, and release gates remain pending or blocked.

## Transcript-polish final re-review evidence (post-`43eeee0`)

| ID | Requirement | Evidence | Current result | Status |
|---|---|---|---|---|
| V02-P09 | Leading-decimal and Unicode-Latin boundaries | RED→GREEN validator, terminology, client, and coordinator regressions cover `.5`/signed leading decimals and `éTBé`; Chinese-adjacent `中TB文` remains eligible | Focused regressions passed | passed-automated |
| V02-P10 | Settings static architecture | `apps/macos/TSB/scripts/settings-static-gate.sh` passed; Xcode enumeration found 0 `SettingsSourceTests` and 23 retained `SettingsBehaviorTests`; retained suite passed 23/23 | Source reads removed from app-hosted XCTest without losing behavior coverage | passed-automated |
| V02-P11 | Final re-review affected aggregate | `/tmp/tsb-final-rereview-focused.xcresult` | **223/223 passed, 0 failed, 0 skipped** | passed-automated |
| V02-P12 | Final re-review full unsigned suite | Fresh `CODE_SIGNING_ALLOWED=NO` run under a 300-second bound; `/tmp/tsb-final-rereview-full.xcresult` | **380/380 passed, 0 failed, 0 skipped** | passed-automated (unsigned only) |
| V02-P13 | Final re-review Debug build and hygiene | Fresh unsigned build at `/tmp/tsb-final-rereview-build`; clean diff check; no resource/build-phase change; bounded additions scan found 0 credential signatures, private paths, logging, or clipboard calls | Unsigned Debug build and stated static checks passed | passed-automated (unsigned only) |

V02-P12 supersedes the earlier blocked unsigned full-suite observations in V02-P02 and V02-P07. Normal signed test/build remains blocked on the copied `onnxruntime.framework` artifact and was not touched. Manual Provider, microphone, target-Mac timing, clipboard/disk, Figma/SwiftUI, Golden Set, M10, merge, and release gates remain pending or blocked.

## Transcript-polish final architecture evidence (post-`551507e`)

| ID | Requirement | Evidence | Current result | Status |
|---|---|---|---|---|
| V02-P14 | Conservative numeric-edit invariant | RED→GREEN validator regressions cover candidate-supported edits in `1e3` and `0x10`, punctuation directly before/after digits, signed and leading-decimal forms; punctuation away from digits remains eligible | Numeric-touching or digit-abutting edits require review; ordinary distant punctuation accepts | passed-automated |
| V02-P15 | Extended-grapheme terminology boundary | RED→GREEN corrector, client, and validator regressions cover decomposed `e\u{301}TBé` and the left-adjacent decomposed form; standalone and Chinese-adjacent aliases remain eligible | Embedded decomposed-Latin alias is not replaced, submitted, or auto-accepted | passed-automated |
| V02-P16 | Final architecture affected aggregate and static gate | `apps/macos/TSB/scripts/settings-static-gate.sh`; `/tmp/tsb-final-architecture-focused.xcresult` | Static gate passed; **229/229 passed, 0 failed, 0 skipped** | passed-automated |
| V02-P17 | Final architecture full suite, build, and hygiene | Fresh bounded `CODE_SIGNING_ALLOWED=NO` run at `/tmp/tsb-final-architecture-full-2.xcresult`; unsigned Debug build at `/tmp/tsb-final-architecture-build`; clean diff and bounded privacy scan | **386/386 passed, 0 failed, 0 skipped**; unsigned Debug build and stated static checks passed | passed-automated (unsigned only) |

V02-P17 is the historical exact-head unsigned automated result at implementation commit `882aec2`. It does not change the release boundary: normal signed test/build remains blocked on the copied `onnxruntime.framework` artifact, and manual Provider, microphone, target-Mac timing, clipboard/disk, Figma/SwiftUI, Golden Set, M10, merge, and release gates remain pending or blocked.

## Acceptance corrections and target-Mac continuation (`817328e`)

| ID | Requirement | Evidence | Current result | Status |
|---|---|---|---|---|
| V02-P18 | Acceptance mode distinguishes first-use permission from denial | RED→GREEN `V02AcceptanceRunnerTests`; configuration and Paraformer preflight remain before permission; first use requests once; denial/restriction writes one constant two-field setup row without recording, copy, persistence, or Provider work | Covered by the current **26/26** runner suite | passed-automated |
| V02-P19 | Timing and cleanup evidence fail closed | Runner preserves a pre-existing durable record, reads Stop timings only from its durable receipt, validates receipt order/source at row creation, and rejects missing/negative first preview or receipt timings in rows and summary; independent review at `817328e` found 0 Critical/Important/Minor | Covered by the current **26/26** runner suite | passed-automated |
| V02-P20 | Current full regression and Debug build boundary | Unsigned result `/tmp/tsb-final-gate.g6I5RE/full.xcresult`; fresh unsigned app under `/tmp/tsb-final-gate.g6I5RE/BuildData`; fresh normal signed attempt under `/tmp/tsb-signed-final.3by8sm/BuildData` | **394/394 passed, 0 failed, 0 skipped** and unsigned Debug build succeeded; normal signed build exited 65 because subcomponent `onnxruntime.framework` is not signed | passed-automated (unsigned only) |
| V02-P21 | Final 10-second target-Mac local-chain rehearsal | Post-`817328e` exclusive JSONL plus durable session metadata; no transcript body recorded in this matrix | First preview 1,546 ms; durable Stop-to-local-final 613 ms; Stop-to-copy 618 ms; one new record/WAV, one clipboard change, immediate/post-organization clipboard equality, no organization recopy | partial-manual |

The final post-review short observation proves that the current unsigned build produces a nonempty preview, durable local final, audio/record bundle and one clipboard delivery on this Mac, and that JSONL timing matches the ordered persisted receipt. It does not pass the 800 ms start-to-preview target: the result was 1,546 ms. The source fixture contains leading low-level audio/silence; the existing onset-trimmed model probe records its first change at 800 ms, but that probe does not substitute for this device result. UI state restoration kept reopening Settings while desktop inspection was attached, so current recording-island visuals remain pending manual visual acceptance. Earlier pre-`47865f8` observations retain only record/WAV/single-copy/clipboard-equality facts; their asynchronous runner timing pairs and the 29.4-second negative result are invalid performance evidence. Organization used the existing loopback `local-acceptance` settings, failed terminally, and did not recopy. A separate single authorized DeepSeek request timed out after 15 seconds with zero response bytes and was not retried, so real Provider acceptance remains blocked.

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
| V02-M10 | Local timing and cycle gates meet the design spec | Historical single authorized formal run stopped on cycle 1 with `preview_missing` (`100/1` requested/completed, 0 passed rows, 0 loopback/external requests, 0 records, 0 automatic clipboard deliveries, 0 non-loopback observations); consumed run is `failed/ineligible`. Runner prevention passed in the historical exact-head 318-test suite; a new attempt requires target-Mac validation of the installed Paraformer bundle, fresh authorization and exclusive artifacts | blocked |

## Completion decision

`BLOCKED — manual acceptance is incomplete.` Current gate HEAD `817328e` has an unsigned automated result of `394/394`, a successful unsigned Debug build, an independent code approval, and one final valid short target-Mac local-chain observation. Stop-to-final, Stop-to-copy, persistence and single-copy behavior passed that rehearsal, but first preview was 1,546 ms against the 800 ms start-based target; current recording-island visuals were not independently captured. These observations do not promote current resident-controls VoiceOver, Provider acceptance, Golden Set, M10, reachable-history owner disposition, normal signed build, merge, or release authorization. Current resident-controls VoiceOver is `pending-manual`; historical broader M07 remains `partial-manual`. V02-M09 remains blocked at 22/30 paired records with no qualified semantic annotations; V02-M10 remains blocked and requires fresh explicit authorization after preview performance, visual acceptance, real Provider reachability, and the signed-build path are resolved.
