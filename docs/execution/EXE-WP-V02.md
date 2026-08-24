# EXE-WP-V02: Island and organization acceptance

- Plan: `docs/superpowers/plans/2026-08-20-tsb-v0.2-implementation-plan.md`
- Spec: `docs/superpowers/specs/2026-08-20-tsb-v0.2-first-principles-design.md`
- Owner: Task 8 automated-evidence implementer
- Reviewer: controller plus target-Mac manual operator
- Status: automated gates passed at `245/245`; release **BLOCKED / manual incomplete**
- Branch: `codex/wp-04-alpha2`
- Evidence-sync HEAD: `753b517998227f9e927a50f48791499d78416b7e`
- Commit: this record is committed with `test(v0.2): record island and organization acceptance`
- Date: 2026-08-24

## Files changed

- Added test-only adversarial Swift string fixtures.
- Updated production parser/validator/client tests to consume every fixture.
- Removed the Task 3 unreported-stop test-of-test and retained cancellation/timeout evidence only through the real `OrganizationClient` path.
- Added this execution record and `docs/testing/tsb-v0.2-acceptance-matrix.md`.
- No production source changed. XcodeGen's ignored generated project has no tracked delta.

## TDD evidence

### Fixture RED

After the parser/validator/client tests referenced the new fixture API and before the fixture source existed:

```bash
xcodebuild -quiet -project apps/macos/TSB/TSB.xcodeproj -scheme TSB \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:TSBTests/OrganizationClientTests \
  -only-testing:TSBTests/OrganizationValidatorTests test
```

Result: exit 65, `OrganizationAdversarialFixtures` not found, `TEST FAILED`.

### Real-path drain RED

The old dedicated unreported-stop test was insufficient because its completion gate was released by test code. After replacing it, the production race was temporarily mutated to start an unowned `URLSession` task and return timeout without cancelling/draining that task.

```bash
xcodebuild -quiet -project apps/macos/TSB/TSB.xcodeproj -scheme TSB \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:TSBTests/OrganizationClientTests/testTimeoutStopsStartedRequestBeforeLateHandlerOutput test
```

Result: exit 65; the named real-client regression failed because `stopLoading` was not observed. The mutation was removed; production source has no final diff.

### GREEN

```bash
xcodegen generate --spec apps/macos/TSB/project.yml
xcodebuild -quiet -project apps/macos/TSB/TSB.xcodeproj -scheme TSB \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:TSBTests/OrganizationClientTests \
  -only-testing:TSBTests/OrganizationValidatorTests \
  -resultBundlePath /tmp/tsb-v02-task8-fixtures.xcresult test
xcrun xcresulttool get test-results summary \
  --path /tmp/tsb-v02-task8-fixtures.xcresult
```

Result: 22 passed, 0 failed, 0 skipped.

## Automated commands and results

```bash
xcodegen generate --spec apps/macos/TSB/project.yml
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -resultBundlePath /tmp/tsb-v02-task8-20260824.xcresult test
```

Result: exit 0; 226 passed, 0 failed; `TEST SUCCEEDED`.

```bash
swift test --package-path probes/sensevoice
swift test --package-path probes/paraformer
```

Result: exit 0; SenseVoice 7/7 and Paraformer 11/11 passed.

```bash
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/tsb-v02-derived CODE_SIGNING_ALLOWED=NO build
```

Result: exit 0; `BUILD SUCCEEDED`. The DerivedData path was absent before the run.

```bash
git diff --check
git status --short
```

Result before and after target-Mac acceptance: `git diff --check` passed and the worktree was clean before this evidence update.

## Runner cleanup and gate adjudication sync

- Runner cleanup commits `23d7406..753b517` are `implemented`, `review-clean`, and `passed-automated`. The exact-HEAD offline clean snapshot passed `245/245`; the fresh Debug build also passed. This does not imply target-device or manual proof.
- Desktop-hosted source reads were obstructed by TCC (`kTCCServiceSystemPolicyAllFiles`, `authValue=0`). Validation used an exact-HEAD `/tmp` source snapshot with the existing dependency lock; no Full Disk Access was requested or granted. This is an evidence-environment fact, not a product permission requirement.
- V02-M02 is `passed-manual (adjudicated)`: three intentionally successful product cycles each had one persisted record, one automatic local copy, immediate clipboard equality and zero organization recopy. Failure attempts are excluded from the passing-cycle count.
- V02-M08 is `blocked`: production parser/validator/persistence/zero-history behavior was observed, but the acceptance window made `3` Provider requests versus exactly `1` allowed. Direct smoke and loopback evidence do not substitute.
- Historical Critical runner incident remains recorded: `3 vs 1` Provider requests, `5 vs 3` records and `5 vs 3` automatic local copies. The runner code is now review-clean/passed-automated; target-device closure is not claimed. Two extra records remain without deletion authorization, and the stopped no-key localhost profile requires action-time confirmation before permanent deletion.
- Task 7 Settings Model-field integrity is reopened as `Important`: Password autofill changed Model before restoration. Code remediation and manual field-semantics verification are required before any new Provider run.

## Automated privacy and adversarial coverage

- The executable outbound test asserts the exact outer keys (`model`, `messages`, `response_format`) and exact inner keys (`schema_version`, `request_id`, `source_text_hash`, `current_segments`, `history_summaries`).
- Forbidden sentinels for API key, language/term metadata, date, audio path, internal session UUID, full old transcript and clipboard content are absent from the encoded body.
- A source-boundary scan found no `RecordedAudio`, `ClipboardService`, `TranscriptRecord`, audio/record filename, AVAudio or FileManager dependency in the network client/validator files.
- Credential-pattern scans of the changed fixtures/tests/docs found zero candidate secrets.
- Unknown candidate/segment IDs, category mixing and malformed JSON are automatically rejected. Empty output needs an allowed reason. Timeout/cancellation must stop a started real client request and cannot accept a released late response.
- Meaning reversal and invented facts remain manual Golden Set judgments; the strict schema cannot infer semantic truth from IDs/hash/categories.

No live provider, DeepSeek call, real Keychain secret, microphone, user session bundle or transcript body was accessed during this automated run. Target-Mac evidence below is a separate manual run.

## Manual target-Mac worksheet — controller must complete

Do not paste transcript bodies, keys or absolute session paths into this record.

| Cycle | Language | Real session ID | `record.json` metadata | `audio.wav` metadata | Immediate clipboard equals `localCleanedText` | Clipboard unchanged after organization | Result |
|---|---|---|---|---|---|---|---|
| 1 | Mandarin | `893903F7-9140-4D62-8968-EE27A2E8D6DB` | `deliveryStatus=copied`; original/SenseVoice/local-cleaned non-empty; cleaned UTF-8 length 421 | 16 kHz, mono, Int16; 85.8 s | SHA-256 equal | Not exercised in this worksheet | M01 pass; M02 adjudicated separately |
| 2 | Cantonese | `7FFB491A-682D-4E15-B693-D11DBF9669C0` | `deliveryStatus=copied`; original/SenseVoice/local-cleaned non-empty; cleaned UTF-8 length 401 | 16 kHz, mono, Int16; 48.2 s | SHA-256 equal | Not exercised in this worksheet | M01 pass; M02 adjudicated separately |
| 3 | Chinese-English mix | `E43B5101-C530-49CE-A090-928B98873B1E` | `deliveryStatus=copied`; original/SenseVoice/local-cleaned non-empty; cleaned UTF-8 length 99 | 16 kHz, mono, Int16; 10.9 s | SHA-256 equal | Not exercised in this worksheet | M01 pass; M02 adjudicated separately |

The three inputs were locally generated acceptance speech played through the target Mac speakers and captured through the real microphone path. No transcript body is recorded here.

| Scenario | Required evidence | Result |
|---|---|---|
| Start new recording during older organization | Old `335D9384-A0A6-45EF-9DEC-3B1FA36E0870` entered `/timeout`; new `ACF4A2B5-C240-42F6-B1BE-FC56FAE434FE` started 13.7 s later while the request was active; the main island visibly switched to the new recording and showed its local-only `恢复整理` action; the new session succeeded locally and the old later failed without overwriting it | pass |
| Per-session local-only | `BD8ADD43-B400-4F93-A796-7A6E0029F69D`; stub `/success` request count stayed 1→1; deterministic/local-points organization succeeded and clipboard remained equal | pass |
| Offline | `D4BD3980-6627-46C1-8B6B-87A1BCF68106`; connection-refused endpoint; local record stayed `copied`, organization `failed`, error code present, clipboard equal; Retry UI not separately captured | partial-manual |
| Authentication rejection | `39B3433F-52D3-4882-B757-90445928182D`; isolated loopback returned HTTP 401; local record stayed `copied`, organization became `failed` with `organization_failed`, clipboard equalled `localCleanedText`, and Retry/Copy/Collapse were visible | pass for 401 fail-closed path; real invalid-provider credential not exercised |
| Timeout | `24DA965E-346C-4DB6-AAE8-900D804C9B68`; one 60 s request; local record stayed `copied`, organization `failed`, clipboard equal, state remained failed after the delayed server response; Retry UI not separately captured | partial-manual |
| Malformed response | `EB3A5FA9-B420-400E-A2F9-671D17E5E761`; one request; local record stayed `copied`, organization `failed`, error code present, clipboard equal; island exposed Retry/Copy/Collapse | pass |
| Three chambers / collapse / reopen | `F2844719-3AB6-471F-952D-3D80A9D9F710` showed all three chambers; `chevron.up` collapsed to `重新打开最近整理结果`, reopening restored the result, and all three copy buttons copied their matching chamber while the prior clipboard was restored after each check | pass |
| Keyboard | The visible acceptance-only toggle exercised the production recording controller; automated Option-Space injection did not reach the Carbon global hotkey, and app-targeted Escape injection did not cancel an active recording. Real Option-Space/Escape remain pending | partial-manual |
| VoiceOver | Status, actions and “推测” label readout | pending-manual |
| Reduce Motion | Island and waveform behavior | pending-manual |
| Controlled DeepSeek-compatible call | Historical direct smoke only; it used synthetic text and did not exercise the production parser/validator DTO. It is not a substitute for the blocked M08 one-request production boundary | historical / non-substitutive |

### Target-Mac island observations

- Recording: the top-notch island showed a live waveform, recording state, preview text, and visible `仅本地` and `停止` actions.
- Post-Stop without remote authorization: the island preserved the original text and showed `需要在设置中授权整理`, `复制原文`, and `收起`.
- Successful loopback organization (`1296A4DE-AFB0-4797-8492-5F1C433C57D5`) displayed the three chambers `原文` / `要点` / `关联`; the speculative connection carried a visible `推测` label. Persistence recorded one point, zero known links and one speculative connection.
- Its outbound audit contained only outer keys `messages`, `model`, `response_format` and payload keys `current_segments`, `history_summaries`, `request_id`, `schema_version`, `source_text_hash`; it had no Authorization header and selected-history count was zero.
- The successful loopback result and the local-only result did not change the clipboard hash.
- The configured result `F2844719-3AB6-471F-952D-3D80A9D9F710` collapsed and reopened through the real island controls. Each chamber copy button produced the matching text; the pre-test clipboard was restored after every check.
- The loopback 401 session `39B3433F-52D3-4882-B757-90445928182D` remained locally copied, persisted a failed organization state, kept clipboard equality with `localCleanedText`, and exposed Retry/Copy/Collapse.
- API settings accessibility tree exposed Provider, Base URL, Model, secure API Key, authorization scope, outbound preview, Save, Cancel, revoke and delete controls.
- Cancel restored the blank persisted draft. A loopback profile saved through the real UI without a key. Delete required a confirmation dialog and then reported `已删除配置与密钥` in an isolated acceptance profile.
- Saving a synthetic key could not complete because the acceptance process was not authorized to access the login Keychain. Production Save/Cancel/Delete/Revoke semantics remain covered by the passing Settings and Keychain automated test groups; the failed manual save did not touch the production Keychain service.

## `v0.2-GS-01` worksheet — controller must complete

| Field | Required threshold | Result |
|---|---:|---|
| Real mixed-language record count | >= 30 | Paired bundle inventory = 17; GS-qualified/annotated count not established |
| Atomic-idea denominator | recorded exactly | PENDING |
| Atomic ideas covered | recorded exactly | PENDING |
| Coverage | >= 95% | PENDING |
| Meaning reversals | 0 | PENDING |
| Invented facts | 0 | PENDING |
| Negation changes | 0 | PENDING |
| Displayed-link denominator | recorded exactly | PENDING |
| Relevant displayed links | recorded exactly | PENDING |
| Link relevance | >= 90% | PENDING |
| Speculative connections isolated | 100% | PENDING |

No automated fixture result fills this worksheet.

## Known warnings

- Xcode selected the first of matching arm64/x86_64 macOS destinations.
- The existing onnxruntime `Versions/Current` framework-symlink warning remains.
- The test host emitted existing linkd/AppIntents registration diagnostics.
- The fresh build reported AppIntents metadata extraction skipped because the app has no AppIntents framework dependency.

All listed automated commands still exited 0 with the stated results.

## Acceptance decision and open risks

`BLOCKED — manual acceptance is incomplete.` Adjudicated M02 passed, while M07 remains pending and M08, M09 and M10 remain blocked. The historical Critical runner incident and the reopened Important Task 7 Model-field integrity subgate remain open. The exact-HEAD automated `245/245` result and Debug build do not promote manual, Provider, accessibility, Golden Set, stability or release status; fresh authorized evidence is still required for the remaining gates.

## Rollback

Revert the Task 8 commit. It changes only tests and documentation; no production behavior or user data migration is involved.
