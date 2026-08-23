# Task 3 Report: Strict Organizer Boundary

## Status

Implemented the strict OpenAI-compatible text-only organizer boundary from base `c8533c14eafd1b87d6beeab8748db87baf8fa414`.

## TDD evidence

- RED: regenerated the Xcode project, then the focused test build failed because `DeterministicOrganizer` and the other organizer-boundary symbols did not exist.
- GREEN: the focused organizer tests pass after the minimum implementation.
- Regression: the complete `TSB` test suite passes.

## Boundary delivered

- Uses the configured URL as the exact chat-completions endpoint.
- Sends only request/schema IDs, current segment ID/text pairs, and explicitly selected candidate ID/summary pairs inside the user payload.
- Intersects selected candidate IDs with frozen local suggestions; an empty selection always sends an empty history array.
- Keeps the API key outside DTOs and places it only in the Authorization header.
- Allows HTTP only for `localhost`, `127.0.0.1`, and `::1`; uses 60-second loopback and 20-second remote request timeouts.
- Validates output schema, request ID, input hash, point numbering, source segment membership, candidate membership, and no-result semantics before resolving candidate IDs locally.
- Provides a deterministic sentence-unit fallback with stable `c1...cn` references and no semantic links or speculative connections.
- Uses native `URLSession`, `URLProtocol`, `CryptoKit`, and `NaturalLanguage`; no package added.

## Verification

```text
xcodebuild -quiet -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:TSBTests/OrganizationClientTests -only-testing:TSBTests/OrganizationValidatorTests -only-testing:TSBTests/DeterministicOrganizerTests test
Result: exit 0

xcodebuild -quiet -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
Result: exit 0

git diff --check
Result: exit 0
```

## Concern

Xcode continues to emit the existing onnxruntime framework `Versions/Current` symlink warning; it does not fail the build or tests.

## Fix Round 1 — reviewed boundary repairs

### Root cause

The redirect regression test crashed the test process, rather than reporting a security assertion, because its `URLProtocol` stub reported both `wasRedirectedTo` and `urlProtocolDidFinishLoading` for one load. Foundation's `URLSession.data(for:delegate:)` continuation then hit `SIGTRAP` on `com.apple.NSURLSession-work` while completing the request twice. A redirect hands the protocol load back to the URL loading system, so the stub must not finish it afterwards.

### RED / GREEN evidence

```text
RED (ordinary failure after removing only the redirect-rejecting task delegate):
xcodebuild -quiet -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:TSBTests/OrganizationClientTests/testRejectsRedirectBeforeAnySecondRequestCanCarryText test
Result: exit 65; 1 failing redirect-boundary test, with no runner restart/crash.

GREEN (restored redirect-rejecting task delegate and corrected the protocol stub lifecycle):
xcodebuild -quiet -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:TSBTests/OrganizationClientTests -only-testing:TSBTests/OrganizationValidatorTests -only-testing:TSBTests/DeterministicOrganizerTests -resultBundlePath /tmp/tsb-task3-focused-2226.xcresult test
Result: exit 0; 17 passed, 0 failed.

xcodebuild -quiet -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -resultBundlePath /tmp/tsb-task3-full-2227.xcresult test
Result: exit 0; 143 passed, 0 failed.

git diff --check
Result: exit 0.
```

### Boundary coverage

- Task-local `URLSessionTaskDelegate` rejects every redirect before a second request can be sent.
- The network payload regenerates `c1...cn` and selected `h1...hn`, retains the local ID maps only for response resolution, sends the locally computed source SHA-256, and requires its exact echo.
- The request races `URLSession.data(for:)` against the 20/60-second wall-clock deadline, cancels the losing network task, and checks cancellation after receiving, decoding, and validating a response.
- Strict response decoding rejects missing, unknown, and category-mixed keys at the top level and inside every organization result object.

### Files changed

- `OrganizationClient.swift`
- `OrganizationValidator.swift`
- `OrganizationClientTests.swift`
- this report and `progress.md`

### Residual concern

The existing onnxruntime `Versions/Current` symlink warning remains unrelated to this boundary and does not affect the 17 focused or 143 full passing tests.

## Fix Round 2 — gated cancellation evidence

### Root cause and mutation

The earlier cancellation test cancelled before proving that a request existed, let its test timeout fire immediately, and only observed an eventual error. It could therefore pass without proving a started network request lost to cancellation or a deadline. The new tests use a protocol-owned start gate, stop callback, release gate, and late-handler-output signal. They catch the mutation `case .timedOut: throw URLError(.cancelled)`: the deadline must win with `.timedOut`, after the request has started and before its blocked handler is released.

Removing the explicit `group.cancelAll()` did not make a valid RED: Swift cancels unfinished task-group children when the throwing group scope exits. The test deliberately asserts the observable URLSession effect (`stopLoading`) instead of treating that redundant call as the behavior contract.

### RED / GREEN evidence

```text
RED (temporary timeout-winner mutation to URLError.cancelled):
xcodebuild -quiet -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:TSBTests/OrganizationClientTests/testTimeoutStopsStartedRequestBeforeLateHandlerOutput test
Result: exit 65; 1 failing test, ordinary assertion failure because the observed error was cancelled instead of timedOut.

GREEN (restored URLError.timedOut):
xcodebuild -quiet -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:TSBTests/OrganizationClientTests/testCancellationStopsStartedRequestBeforeLateHandlerOutput -only-testing:TSBTests/OrganizationClientTests/testTimeoutStopsStartedRequestBeforeLateHandlerOutput -resultBundlePath /tmp/tsb-task3-round2-gated.xcresult test
Result: exit 0; 2 passed, 0 failed.

xcodebuild -quiet -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:TSBTests/OrganizationClientTests -only-testing:TSBTests/OrganizationValidatorTests -only-testing:TSBTests/DeterministicOrganizerTests -resultBundlePath /tmp/tsb-task3-round2-focused.xcresult test
Result: exit 0; 18 passed, 0 failed.

xcodebuild -quiet -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -resultBundlePath /tmp/tsb-task3-round2-full.xcresult test
Result: exit 0; 144 passed, 0 failed.

git diff --check
Result: exit 0.
```

### Coverage added

- Caller cancellation occurs only after the custom protocol has recorded request start; it then must observe `stopLoading`, throw, and remain unable to return the released late handler response.
- Timeout is released only after request start; it must observe `stopLoading`, return `URLError.timedOut`, and remain unable to return the released late handler response.

### Files changed

- `OrganizationClientTests.swift`
- this report and `progress.md`

## Fix Round 3 — bounded completion evidence

### Root cause and fix

Round 2 waited for `task.value` while the protocol handler still waited on its release gate. A regression could therefore call `stopLoading` without resolving the URLSession continuation and hang the test after its stop assertion. The tests now release the handler immediately after `stopLoading`, then observe the operation result through a one-second XCTest completion expectation. A missing completion fails boundedly; a late handler output is still released and observed only after the operation has failed.

### RED / GREEN evidence

```text
RED (temporary mutation delays the timeout branch for 60 seconds after request stop):
xcodebuild -quiet -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:TSBTests/OrganizationClientTests/testTimeoutStopsStartedRequestBeforeLateHandlerOutput test
Result: exit 65; 1 bounded ordinary test failure, rather than a runner hang.

GREEN (restored immediate timeout result):
xcodebuild -quiet -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:TSBTests/OrganizationClientTests/testCancellationStopsStartedRequestBeforeLateHandlerOutput -only-testing:TSBTests/OrganizationClientTests/testTimeoutStopsStartedRequestBeforeLateHandlerOutput -resultBundlePath /tmp/tsb-task3-round3-gated.xcresult test
Result: exit 0; 2 passed, 0 failed.

xcodebuild -quiet -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:TSBTests/OrganizationClientTests -only-testing:TSBTests/OrganizationValidatorTests -only-testing:TSBTests/DeterministicOrganizerTests -resultBundlePath /tmp/tsb-task3-round3-focused.xcresult test
Result: exit 0; 18 passed, 0 failed.

xcodebuild -quiet -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -resultBundlePath /tmp/tsb-task3-round3-full.xcresult test
Result: exit 0; 144 passed, 0 failed.

git diff --check
Result: exit 0.
```

### Files changed

- `OrganizationClientTests.swift`
- this report and `progress.md`
