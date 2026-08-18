# TSB Engineering Standard

Version: 2.0

Effective date: 2026-08-19

## 1. Meaning of “large-company standard”

For TSB it means reproducible builds, explicit ownership, testable interfaces, privacy boundaries and reversible Git changes. It does not mean adding services, frameworks, meetings or documents that the 0.1 product does not need.

0.1 is a native macOS application. It has a UI layer and a local core layer; it has no traditional remote backend. Backend-style requirements apply to the local session coordinator, ASR, persistence and clipboard delivery.

## 2. Single sources of truth

- Product and architecture requirements: `docs/specs/`.
- Intended implementation: `docs/plans/`.
- Important technical choices: `docs/decisions/`.
- Actual work, deviations and commit mapping: `docs/execution/`.
- Test and performance proof: `evidence/`.
- Formal product code: `apps/macos/TSB/` only.

If these sources conflict, execution stops until the spec or implementation is corrected. Chat messages and old files are not release authority.

## 3. Git and review

- `main` must remain reviewable and buildable after code exists.
- Working branches use `codex/<scope>`.
- Commits use `type(scope): summary` and express one independently reversible intent.
- Every work package has one code owner and one reviewer; shared orchestrator and build files have one writer at a time.
- Stage only explicit paths. Never use a blind `git add .` before publication.
- Never force-push `main` or discard another repository history to resolve a conflict.
- Rollback is a revert commit or a documented migration, not manual file replacement.

## 4. Code boundaries

- UI renders immutable state and sends commands; it does not own ASR, persistence or clipboard side effects.
- `SessionCoordinator` is the only owner of session transitions and automatic delivery.
- Audio, VAD, ASR, cleanup, persistence and clipboard components communicate through narrow value-type contracts.
- Swift concurrency ownership is explicit. UI updates occur on `MainActor`; mutable session state belongs to an actor or a single serialized executor.
- Do not create an interface, registry or factory until a second real implementation requires it, except at a third-party trust boundary that must be test-isolated.

## 5. Traceability and observability

Each session has a non-sensitive `sessionID`; each segment has a monotonically increasing sequence. Logs may record stage, duration, model/version, audio duration, output character count and error category. Logs must not record audio, full transcripts, clipboard content or API keys.

Every work package maps:

```text
WP → spec requirement → files → tests → commit → AC → evidence
```

The mapping lives in one execution record; duplicate status tables are not maintained.

## 6. Privacy and repository hygiene

- API keys are stored only in macOS Keychain.
- Audio, real transcripts, runtime databases, model weights, DMGs, signing assets and raw benchmark recordings are never committed.
- Third-party source copied into the product requires a pinned source commit, license and provenance notice.
- External reference applications are not nested Git repositories inside the product repository.
- Successful audio is deleted only after transcript persistence succeeds; failed audio follows the approved 24-hour policy.

## 7. Quality gates

Before each work-package commit:

1. Focused tests pass.
2. `git diff --check` passes.
3. Staged paths match the declared ownership boundary.
4. No secrets, user content, binary models or generated artifacts are staged.
5. The execution record names the test command and evidence path.

Before merging a stage:

1. Clean checkout can reproduce project generation and Debug build.
2. Unit and contract tests pass.
3. Relevant failure and idempotency tests pass.
4. Acceptance criteria have evidence or remain explicitly not entered.
5. Sol reviews the real diff and outputs, not only an agent summary.

## 8. Definition of done

A task is done only when its required behavior and critical failure path are tested, privacy boundaries hold, documentation matches behavior, evidence is indexed, and the change can be reverted without deleting unrelated user work.
