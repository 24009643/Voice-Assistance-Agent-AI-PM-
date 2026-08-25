# Task 5 Report — Production wiring and timing evidence

## RED

- Added source-bound runtime wiring coverage and JSONL metadata allowlist/privacy coverage.
- Default selected-test invocation reached the existing malformed `onnxruntime.framework` signing failure before tests. The signing-disabled rerun then failed as intended: seven missing AppController wiring assertions and one missing JSONL field allowlist assertion.

## GREEN

- `AppController` now supplies current terminology, obtains one endpoint-bound Keychain secret only for an eligible remote request, constructs `TranscriptPolishClient` per request, and reports only endpoint/provider metadata to the coordinator before transport.
- `AppSnapshot` carries polish state and delivery source for observability without a layout or island-control change.
- Acceptance JSONL emits `stop_to_local_final_ms`, `polish_elapsed_ms`, `stop_to_copy_ms`, `delivery_source`, and `polish_state`; the allowlist test rejects submitted/corrected/local/polished text fields.
- Focused signing-disabled test command passed 21 tests with zero failures: 4 `SettingsSourceTests` and 17 `V02AcceptanceRunnerTests`.

## Build

- Default Debug build reached the existing copied `onnxruntime.framework` signature failure (`code object is not signed at all`).
- The bounded fallback `CODE_SIGNING_ALLOWED=NO` Debug build succeeded. No dependency artifact was changed.

## Self-review / concerns

- `git diff --check` is clean. No SDK, retry, logging, audio/network DTO, island layout, or control was added.
- Existing coordinator code remains the owner of `ContinuousClock` and the 1.5-second deadline; this task only provides production wiring and observable evidence.
- Automated checks prove wiring/schema boundaries, not a user-present latency or Provider acceptance run.

## Commit

`feat(v0.2): wire bounded transcript polish runtime`

## Fix round 1 — reviewer changes

### RED

- Checked the pre-fix committed sources: they had no `Dependencies.updateDelivery` composition-root wiring, no client `onRequestPrepared` hook, and no delivered-preview JSON keys or typed validity predicate.
- Added narrow behavior tests for a restarted-store receipt load; request-prepared callback ordering/count and invalid-request zero transport; loopback/local-only/remote Keychain-load counts; and separate missing source, missing state, invalid pair, JSON type/domain, and M10 rejection cases.
- The first selected test invocation failed during test compilation because the new remote fixture named the cloud consent constant incorrectly; corrected that test fixture before production work. The next focused compile exposed the intended escaping boundary for the new hook, then passed after the dependency callback was made explicitly escaping.

### GREEN

- `AppController` now wires `updateDelivery` directly to `TranscriptStore.updateDelivery(id:status:receipt:)`; the restarted-store test proves the receipt survives a new store instance.
- `TranscriptPolishClient` invokes a parameterless request-prepared callback exactly once after local validation/body construction and immediately before transport. AppController supplies the coordinator callback there; the callback receives no text, key, or path.
- Endpoint-bound secret loading remains zero for `localOnly` and loopback, and exactly one for an eligible remote polish dispatch.
- Durable local delivery now publishes explicit `notRequested` polish state; acceptance records use optional typed source/state values, encode missing evidence as `null`, reject inconsistent source/state pairs, and rename the delivered-preview comparisons to `immediate_equals_delivered` and `post_organization_equals_delivered`.
- Focused signing-disabled suite passed **180 tests** with zero failures: 6 `TranscriptPolishClientTests`, 4 `SettingsSourceTests`, 23 `SettingsBehaviorTests`, 17 `TranscriptStoreTests`, 18 `V02AcceptanceRunnerTests`, and 112 `SessionCoordinatorTests`.

### Build / self-review

- Default Debug build again failed only at the known copied `onnxruntime.framework` signing defect (`code object is not signed at all`); the signing-disabled Debug build succeeded.
- `git diff --check` is clean. Scope remains limited to composition, client dispatch timing, snapshot/acceptance evidence, and focused tests; no UI/layout controls, dependencies, retries, or text/key/path logging were added.
