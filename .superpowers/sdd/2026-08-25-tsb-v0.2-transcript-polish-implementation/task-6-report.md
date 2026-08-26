# Task 6 Report — Full gates and conservative evidence sync

## Commands and results

- Normal focused aggregate: stopped during `CodeSign TSB.app` with `code object is not signed at all` in the copied `onnxruntime.framework`.
- Focused aggregate with `CODE_SIGNING_ALLOWED=NO`: **208 passed, 0 failed, 0 skipped**.
- Normal full suite with `/tmp/tsb-polish-full.xcresult`: same signing failure before tests ran.
- Normal Debug build: same signing failure.
- Signing-disabled full suite with `/tmp/tsb-polish-full-unsigned.xcresult`: intentionally interrupted after it stalled in `SettingsSourceTests.testAPIKeyUsesNonLoginContentTypeAndModelIsNotACredentialField`; no final full-suite count exists.
- Signing-disabled Debug build at `/tmp/tsb-polish-build-unsigned`: succeeded.
- `git diff --check eba721b..323d7bb`: clean. Pre-documentation `git status --short`: empty.

## Bounded privacy scan

Range `eba721b..323d7bb`, production and test additions: 0 credential signatures, 0 Bearer value literals, 0 private absolute-path literals, and 0 added production logging calls. The polish request has an explicit candidates/terminology whitelist; no audio, path, history, clipboard, record, or session-ID request field was found. The diff adds one coordinator delivery-axis `dependencies.copy(deliveredText)` call and no direct `clipboard.copy` addition.

This is static evidence only. It does not prove real Provider, microphone, clipboard/disk, or Figma/manual behavior.

## Pending / concerns

- Full signing-disabled suite is not a pass because it stalled and was terminated.
- Normal signed test/build remains blocked by the copied `onnxruntime.framework` artifact.
- Real Provider, microphone quality, target-Mac timing, clipboard/disk observation, Figma/SwiftUI, Golden Set, M10, merge/push/release remain pending or blocked.

## Commit

`1358a4765cfe91f475de42f8c4ff85a29f106ed9` — `docs(v0.2): record transcript polish gates`

## Final fixes

- Closed the request-preparation cancellation race: cancellation is rechecked immediately before transport, and a deterministic callback-time cancellation test observes zero requests.
- Moved endpoint-bound Keychain loading off the MainActor after a MainActor eligibility snapshot. Suspended key-load deadline and revoke tests deliver the durable local text once, record content-free terminal metadata after copy, and prevent late dispatch.
- Made every local fallback non-stalling: timeout, cancellation, review-required, validation rejection, transport/configuration failure, and accepted-polish save failure copy and sample Stop-to-copy before best-effort terminal persistence. Accepted polish still requires a durable save before polished delivery.
- Protected signed, decimal, and grouped numeric scalars; reused one exact Latin endpoint-boundary predicate across correction, request relevance, coordinator filtering, and validator terminology edits.
- Classified real strict validation/shape/overflow failures as `rejected`, transport/configuration failures as `failed`, and deadline completion as `timedOut` even before dispatch metadata exists. Added backward-compatible `selectedHistoryRecordCount = 0` and renamed `clipboard_not_local` to `clipboard_not_delivered`.

### Final verification

- Fresh signing-disabled affected-suite aggregate: **218 passed, 0 failed, 0 skipped**; result bundle `/tmp/tsb-final-fixes-focused-final.xcresult`.
- Fresh signing-disabled Debug build: succeeded at `/tmp/tsb-final-fixes-build-final`.
- `git diff --check`: clean. The approved five-source bundle-resource experiment was fully reverted; `project.yml` and the generated project contain no final resource-experiment diff.
- Bounded added-production-line scan from `1358a47`: 0 provider-token signatures, 0 Bearer value literals, 0 PEM private-key markers, 0 private `/Users/` paths, 0 `.env` references, 0 logging calls, and 0 added clipboard calls.

### Full-suite blocker

The approved minimal hypothesis was tested exactly once: the five source files inspected by `SettingsSourceTests` were added to the `TSBTests` Copy Bundle Resources phase, the project was regenerated, and the isolated named test was run. Xcode completed the test invocation instead of stalling, but warned that each `.swift` file “cannot be processed by a Copy Bundle Resources build phase”; the test then failed because the requested bundle resource URL was nil. Per the stop condition, the experiment was reverted and no alternative was stacked. Therefore no new full-suite count or pass exists.

Normal signed test/build was not claimed or repaired; the known copied `onnxruntime.framework` signing defect remains. Real Provider, microphone quality, target-Mac timing, clipboard/disk observation, Figma/SwiftUI, Golden Set, M10, merge/push/release remain pending or blocked.

## Final re-review fixes

- Added RED regressions for `.5` to `,5`, sign changes on `+.5`, and separator changes on ASCII- and Unicode-minus leading decimals. All four were accepted before the immutable-number expression admitted leading-decimal forms; the minimal expression change now rejects all four.
- Added RED regressions proving `TB` inside `éTBé` was locally replaced, submitted by the coordinator/client, and automatically accepted from Provider output. The shared boundary predicate now uses Unicode `Latin` script membership for letters while preserving the designed Chinese-adjacent `中TB文` correction.
- Removed only the four source-reading methods and their helpers from app-hosted `SettingsSourceTests`; all `SettingsBehaviorTests` remain. `apps/macos/TSB/scripts/settings-static-gate.sh` now runs the exact prior positive and negative source assertions from the repository shell with fixed-string `rg` checks.

### Re-review verification

- Static settings gate: passed. Shell syntax check: passed.
- Xcode test enumeration: **0** `SettingsSourceTests` selectors and **23** `SettingsBehaviorTests` selectors. Retained settings behavior suite: **23 passed, 0 failed, 0 skipped**.
- Fresh signing-disabled affected aggregate: **223 passed, 0 failed, 0 skipped**; result bundle `/tmp/tsb-final-rereview-focused.xcresult`.
- Fresh signing-disabled full macOS suite under a 300-second bound: **380 passed, 0 failed, 0 skipped**; result bundle `/tmp/tsb-final-rereview-full.xcresult`.
- Fresh signing-disabled Debug build: succeeded at `/tmp/tsb-final-rereview-build`.
- `git diff --check`: clean. No `project.yml`, generated-project, resource, fixture, or build-phase change was added.
- Bounded additions scan from `43eeee0`: 0 provider-token signatures, Bearer value literals, PEM private-key markers, private `/Users/` paths, `.env` references, production logging calls, or added clipboard calls. The request DTO and whitelist were unchanged.

Normal signed test/build and all manual/release gates were intentionally untouched and remain as recorded above.

## Final architecture correction

- Replaced numeric-format enumeration as the automatic-acceptance authority with one conservative invariant: every edit that touches or directly abuts a decimal digit requires review. RED regressions covered candidate-supported `1e3`/`0x10` marker edits and punctuation immediately before/after digits; ordinary punctuation away from digits remained accepted. Existing URL/email immutability checks remain strict.
- Changed terminology endpoint checks to inspect adjacent extended grapheme characters and classify a boundary as Latin when any scalar in that grapheme has Unicode Latin script membership. RED regressions proved the left-adjacent decomposed `e\u{301}` form was previously replaced, submitted, and auto-accepted; the corrected parser/corrector, client, and validator paths now keep embedded aliases irrelevant while preserving standalone and Chinese-adjacent behavior.

### Final architecture verification

- Static settings gate: passed.
- Fresh signing-disabled affected aggregate: **229 passed, 0 failed, 0 skipped**; result bundle `/tmp/tsb-final-architecture-focused.xcresult`.
- Fresh signing-disabled full macOS suite under a 300-second bound: **386 passed, 0 failed, 0 skipped**; result bundle `/tmp/tsb-final-architecture-full-2.xcresult`.
- Fresh signing-disabled Debug build: succeeded at `/tmp/tsb-final-architecture-build`.
- `git diff --check`: clean. No `project.yml`, generated-project, resource, fixture, or build-phase change was added. The bounded changed-production-file scan found no credential signature, Bearer value, PEM private-key marker, private `/Users/` path, `.env` reference, logging call, or clipboard call.

Implementation commit: `882aec258ad3d1111d210ba11f6a1a740c535fc3`.

Normal signed test/build and all manual/release gates were intentionally untouched and remain pending or blocked as recorded above.
