# EXE-WP-V02: Island and organization acceptance

- Plan: `docs/superpowers/plans/2026-08-20-tsb-v0.2-implementation-plan.md`
- Spec: `docs/superpowers/specs/2026-08-20-tsb-v0.2-first-principles-design.md`
- Owner: Task 8 automated-evidence implementer
- Reviewer: controller plus target-Mac manual operator
- Status: automated gates and real-microphone gate passed; release **blocked / manual incomplete**
- Branch: `codex/wp-04-alpha2`
- Tested baseline: `c2b904f`
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
| 1 | Mandarin | `893903F7-9140-4D62-8968-EE27A2E8D6DB` | `deliveryStatus=copied`; original/SenseVoice/local-cleaned non-empty; cleaned UTF-8 length 421 | 16 kHz, mono, Int16; 85.8 s | SHA-256 equal | Not exercised; organization required authorization | M01 pass / M02 pending |
| 2 | Cantonese | `7FFB491A-682D-4E15-B693-D11DBF9669C0` | `deliveryStatus=copied`; original/SenseVoice/local-cleaned non-empty; cleaned UTF-8 length 401 | 16 kHz, mono, Int16; 48.2 s | SHA-256 equal | Not exercised; organization required authorization | M01 pass / M02 pending |
| 3 | Chinese-English mix | `E43B5101-C530-49CE-A090-928B98873B1E` | `deliveryStatus=copied`; original/SenseVoice/local-cleaned non-empty; cleaned UTF-8 length 99 | 16 kHz, mono, Int16; 10.9 s | SHA-256 equal | Not exercised; organization required authorization | M01 pass / M02 pending |

The three inputs were locally generated acceptance speech played through the target Mac speakers and captured through the real microphone path. No transcript body is recorded here.

| Scenario | Required evidence | Result |
|---|---|---|
| Start new recording during older organization | Both session IDs, timestamps and main-island ownership | pending-manual |
| Per-session local-only | Session ID and runtime proof of zero remote request | pending-manual |
| Offline | Local save/copy, failure UI and retry observation | pending-manual |
| Invalid key | Local save/copy, authorization failure and retry observation | pending-manual |
| Timeout | Local save/copy, timeout UI and late-result suppression observation | pending-manual |
| Malformed response | Local save/copy, validation failure and retry observation | pending-manual |
| Three chambers / collapse / reopen | Full-screen capture proved notch-attached recording and authorization-required result states; configured three chambers/collapse/reopen are still pending | partial-manual |
| Keyboard | The visible acceptance-only toggle exercised the production recording controller; automated Option-Space injection did not reach the Carbon global hotkey, so real Option-Space/Escape remain pending | partial-manual |
| VoiceOver | Status, actions and “推测” label readout | pending-manual |
| Reduce Motion | Island and waveform behavior | pending-manual |
| Controlled DeepSeek-compatible call | The source Keychain item exists, but both the XCTest process and system CLI were denied secret access (`-25293` / exit 51); this acceptance attempt stopped before dispatch and issued zero provider requests, the temporary test was removed, and a credential-pattern scan found no candidates | blocked |

### Target-Mac island observations

- Recording: the top-notch island showed a live waveform, recording state, preview text, and visible `仅本地` and `停止` actions.
- Post-Stop without remote authorization: the island preserved the original text and showed `需要在设置中授权整理`, `复制原文`, and `收起`.
- API settings accessibility tree exposed Provider, Base URL, Model, secure API Key, authorization scope, outbound preview, Save, Cancel, revoke and delete controls.
- Cancel restored the blank persisted draft. Delete required a confirmation dialog and then reported `已删除配置与密钥` in an isolated acceptance profile.
- Saving a synthetic key could not complete because the acceptance process was not authorized to access the login Keychain. Production Save/Cancel/Delete/Revoke semantics remain covered by the passing Settings and Keychain automated test groups; the failed manual save did not touch the production Keychain service.

## `v0.2-GS-01` worksheet — controller must complete

| Field | Required threshold | Result |
|---|---:|---|
| Real mixed-language record count | >= 30 | Paired bundle inventory = 7; GS-qualified/annotated count not established |
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

`BLOCKED — manual acceptance is incomplete.` The three-session real-microphone chain and immediate pasteboard proof passed. The island recording and authorization-required states, settings Cancel and isolated Delete were observed. Completion is still blocked by the controlled provider call, configured successful-organization clipboard proof, local-only/offline/failure-mode runtime observations, three-chamber/accessibility completion, a qualified/annotated 30-record semantic Golden Set, and the 100-cycle/timing gates.

## Rollback

Revert the Task 8 commit. It changes only tests and documentation; no production behavior or user data migration is involved.
