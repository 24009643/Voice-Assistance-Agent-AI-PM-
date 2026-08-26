# SDD ledger — plan: docs/superpowers/plans/2026-08-25-tsb-v0.2-transcript-polish-implementation.md

Spec: docs/superpowers/specs/2026-08-25-tsb-v0.2-transcript-polish-design.md
Start HEAD: 05fb857

## Pre-flight interface scan

| Scope | Producer / consumer | Finding |
|---|---|---|
| Task 1 internal | tests name terminology/model/store behavior; code shapes and limits are specified | consistent |
| Task 2 internal | tests cover outer/inner contract; client/validator interfaces and limits are specified | consistent |
| Task 3 internal | tests cover purpose separation and secret retention; settings/dispatch interfaces are specified | consistent |
| Task 4 internal | tests cover lease races and lifecycle; dependencies and state are specified | consistent |
| Task 5 internal | tests cover production wiring and metadata; no island layout files are touched | consistent |
| Task 6 internal | aggregate/full/review/evidence steps preserve manual gates | consistent |
| Tasks 1 -> 2 | terminology/candidate/edit/outcome models feed validator/client | consistent |
| Tasks 1 -> 3 | terminology parser/model feeds stored functional configuration | consistent |
| Tasks 1 -> 4 | record/store/delivery models feed lease persistence | consistent; Task 4 may extend but must preserve legacy defaults |
| Tasks 1 -> 5 | delivery receipt fields feed acceptance metrics | consistent |
| Tasks 2 -> 4 | request/outcome feed injected polish dependency | consistent |
| Tasks 2 -> 5 | client feeds AppController production wiring | consistent |
| Tasks 3 -> 4 | settings terminology and local-only eligibility feed coordinator dependency | consistent |
| Tasks 3 -> 5 | AppController dispatch boundary is completed by production wiring | consistent; Task 5 must not duplicate eligibility logic |
| Tasks 4 -> 5 | coordinator lease/timings feed AppSnapshot and acceptance runner | consistent |
| Tasks 1-5 -> 6 | commits/tests/build feed conservative evidence | consistent |

Ruling: Use a fresh sequential implementer for each task as required by subagent-driven-development, while keeping only one active production writer and handing off exact interfaces through task briefs — this overrides the plan's Token ROI line saying one implementer retains Tasks 1-5 context — cost if wrong: extra onboarding tokens, mitigated by narrow artifact-only briefs.

Task 1: complete (commits 05fb857..dfaacb1, review clean)
Task 2: complete (commits dfaacb1..d63ae9c, review clean)
Task 3: complete (commits d63ae9c..386b25b, review clean)
Task 4: complete (commits 386b25b..11ab124, review clean)
Task 5: complete (commits 11ab124..323d7bb, review clean; deferred clipboard label corrected in final fixes)
Task 6: complete for the requested unsigned automated scope (product implementation 882aec2; acceptance corrections through 817328e; current static gate, acceptance-runner 26/26, full suite 394/394, fresh unsigned Debug build, and independent code review passed; signed/manual/release gates remain)

Ruling: Replace app-hosted runtime reads of Desktop source files with exact source files copied into the test bundle, because the isolated test reproducibly blocks in kernel open(2) while shell reads the same file instantly; cost if wrong: small XcodeGen resource configuration, removed if the bundle-resource reproduction does not pass.
Ruling: After repeated numeric-form edge findings, enforce the invariant that no automatic edit may touch or directly abut a decimal digit instead of enumerating number grammars; cost if wrong: conservative fallback for harmless formatting near digits, preferred over silent numeric corruption.
Ruling: The direct .swift test-resource hypothesis was rejected by Xcode and fully reverted; source-string assertions now run as a standalone static gate while app-hosted XCTest retains behavior tests, avoiding Desktop runtime reads without weakening the checks.
Ruling: In explicitly opted-in DEBUG acceptance runs, distinguish first-use microphone permission from denial, request first-use permission once only after configuration/model preflight, and write a two-field setup failure on denial instead of silently exiting; cost if wrong: one acceptance-only system prompt, bounded by the explicit environment opt-in and existing macOS permission UI.
Ruling: Treat the persisted delivery receipt as the sole Stop-timing authority, reject missing/negative/inverted or source-mismatched receipt data at the cycle boundary, and preserve any record already durable before the runner's controlled Stop; cost if wrong: a conservative failed rehearsal instead of an unsafe cleanup or false M10 pass.

Outcome: the isolated test completed under the exact five-file resource experiment, but Xcode could not process `.swift` files in Copy Bundle Resources and bundle lookup returned nil. The experiment was removed as specified; no alternative was stacked.

Correction: source-text assertions now run from the repository shell in `apps/macos/TSB/scripts/settings-static-gate.sh`; app-hosted enumeration contains no `SettingsSourceTests` selector and retains all 23 `SettingsBehaviorTests`. This architecture passed the static gate and the fresh 380-test unsigned full suite without a resource or build-phase change.

Final architecture correction: automatic acceptance now has one conservative digit invariant—any edit touching or directly abutting a decimal digit requires review—and terminology boundaries inspect adjacent extended grapheme characters for Unicode Latin scalars. The static gate, 229-test affected aggregate, 386-test full unsigned suite, and fresh unsigned Debug build passed; signed/manual/release gates remain unchanged.

Target-Mac continuation through `817328e`: first-use acceptance permission, durable-record preservation, row-level receipt validation, receipt-source matching, and negative/missing first-preview rejection were implemented RED→GREEN and independently approved. The current static gate, acceptance-runner 26/26, full unsigned suite 394/394, and fresh unsigned Debug build passed. Earlier pre-`47865f8` short runs preserve only record/WAV/single-copy/clipboard-equality observations; their runner timing pairs were invalid and are not performance evidence. The final post-review 10-second rehearsal persisted one record and one WAV, copied once, kept immediate and post-organization clipboard equality, and recorded ordered durable receipt timings of 613 ms Stop-to-local-final and 618 ms Stop-to-copy. First preview was 1,546 ms, so the 800 ms gate did not pass. The fixed source WAV contains material leading low-level audio/silence and prior model probe evidence reaches its first change at 800 ms on an onset-trimmed fixture; no product debounce or artificial preview was added. Current settings remained local-polish with a loopback organization endpoint, so organization ended failed without recopy; the separate authorized DeepSeek probe timed out after 15 seconds with zero response bytes and was not retried. A fresh current-HEAD normal signed build under `/tmp/tsb-signed-final.3by8sm/BuildData` exited 65 because subcomponent `onnxruntime.framework` is not signed, so the upstream framework packaging blocker remains; the installed signed app was not overwritten. Manual visual/accessibility, Provider, Golden Set, M10, merge, push, and release gates remain open.
