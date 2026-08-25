# Task 2 report

Files: `TranscriptPolishClient.swift`, `TranscriptPolishValidator.swift`, focused client/validator tests, and `project.yml` (test-target generated Info.plist setting). Xcode project regenerated; folder-synchronised project required no tracked `.pbxproj` diff.

RED: `xcodegen generate --spec apps/macos/TSB/project.yml && CODE_SIGNING_ALLOWED=NO xcodebuild ... /tmp/tsb-polish-task2-red ... test` failed before new interfaces compiled because the baseline test target lacked an Info.plist.

GREEN: `xcodebuild CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -derivedDataPath /tmp/tsb-polish-task2-green -only-testing:TSBTests/TranscriptPolishValidatorTests -only-testing:TSBTests/TranscriptPolishClientTests test` passed: 10 tests, 0 failures. `git diff --check` passed.

Self-review: separate client, strict allowlisted DTO shapes, fixed byte/candidate/terminology limits, HTTPS-or-loopback gate, redirect delegate, single-choice response, no retries/logging/SDK/tools/streaming. Validator retains context-only rewrites as review-required and rejects immutable token changes.

Concern: this task implements only the contract boundary; the coordinator-owned deadline, persistence, delivery lease, and settings consent are intentionally left for later tasks.

## Fix round 1

RED added regressions for streamed-overflow handling, loopback eligibility, irrelevant/empty terminology, immutable small edits, JSON booleans/overflow, insertions, unanchored candidate evidence, and Latin-only formatting. The original RED is labelled inconclusive: Info.plist failed before missing-interface evidence.

GREEN: `xcodebuild CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -derivedDataPath /tmp/tsb-polish-task2-fix -only-testing:TSBTests/TranscriptPolishValidatorTests -only-testing:TSBTests/TranscriptPolishClientTests test` passed 13 tests, 0 failures. `git diff --check` passed.

Fixes: response reads through `URLSession.bytes` with expected-length and per-byte 64 KiB rejection; system contract now declares strict shape and prohibitions; terminology requires nonempty, relevant exact values; immutable regex is corrected; candidate support uses one contiguous scalar-anchor slice; changed-unit arithmetic, edit range arithmetic, and JSON booleans are safe; formatting permits Latin case only. Redirect delegate remains covered by the existing client pattern; a dedicated redirect protocol regression is not present because the existing test stub does not model redirects.

## Fix round 2

Stall diagnosis: the first redirect stub synchronously delivered a redirect and left `URLSession.bytes` awaiting completion after its delegate rejected it. The task-owned `xcodebuild` and TSB processes were terminated; no unrelated process was touched. The replacement copies the Organization stub lifecycle (async handler, `NSLock` stopped state, `stopLoading`) and the test observes origin, asserts `[origin]`, then cancels its task.

RED coverage adds exact system-contract clauses, origin-only redirect behavior, multi-chunk body overflow (`32768 + 32769` bytes), actual candidate-hash mutation, invalid terminology network prohibition, and prefix/suffix candidate-boundary adversaries. GREEN: the bounded focused command passed 15 tests, 0 failures; `git diff --check` passed. Self-review: contract now includes schema/order/immutables/limits/ratio/anchors; boundary evidence enforces prefix/suffix at text edges; redirect target is never requested; tests no longer rely on whole-buffer overflow or a handler that masks network reachability.

## Fix round 3

RED expands the request-contract assertions to every fixed schema/edit/limit/immutability/anchor/non-inference clause and changes redirect verification to wait for the production delegate's rejection callback. The internal callback is default-inert and invokes immediately before `completionHandler(nil)`.

GREEN: `xcodebuild CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -derivedDataPath /tmp/tsb-polish-task2-round3 -only-testing:TSBTests/TranscriptPolishValidatorTests -only-testing:TSBTests/TranscriptPolishClientTests test` passed 15 tests, 0 failures. `git diff --check` passed. Self-review: provider instructions now enumerate the complete required contract; redirect test observes actual delegate rejection before asserting origin-only routing and cancelling.
