# EXE-WP-02: Deferred SenseVoice G0 gate

- Plan: `docs/plans/2026-08-19-g0-foundation-and-sensevoice-probe.md`
- Owner: GPT-5.5 probe/bootstrap, Luna evidence, Sol integration
- Reviewer: independent Sol reviewers
- Status: blocked
- Branch: `codex/repo-foundation`
- Commits: `cbf0516` through `024b8a3`; final reproducible record head `024b8a3`
- Started: 2026-08-19
- Finished: 2026-08-19

## Files changed

- Added `evidence/WP-02-AC-ASR-001-sensevoice-probe.md`.
- Added this execution record.
- Linked the pending evidence in `docs/decisions/ADR-0002-sensevoice-baseline.md`; ADR status remains Proposed.
- No model, audio, raw transcript or generated result was added.

## Commands and results

- `sh -n scripts/bootstrap-sensevoice-model.sh`: passed, exit 0.
- `scripts/bootstrap-sensevoice-model.sh --self-check`: passed, exit 0.
- `swift test --package-path probes/sensevoice`: passed, 5 tests and 0 failures.
- `swift run --package-path probes/sensevoice SenseVoiceProbe --help`: passed, exit 0; usage printed without model files.
- All package tests, `--help`, shell syntax and bootstrap self-check passed again after WP-02 was fast-forwarded into the integration branch at `024b8a3`.
- Real model bootstrap, `--verify-only`, audio decode and G0 benchmark commands: not run by explicit user ruling.
- Read-only environment snapshot: macOS 26.5.2 (build 25F84), Xcode 26.6 (build 17F113), Apple Swift 6.3.3.

## Acceptance criteria and evidence

- Evidence: `evidence/WP-02-AC-ASR-001-sensevoice-probe.md`.
- Tooling checks pass, but G0 is **not run**.
- Real decode, RTF, active memory delta, installed-size, truncation/resource-release and language-accuracy gates remain unmeasured.
- Absolute process peak RSS is not treated as active ASR memory delta; a future run requires a pre-load baseline or must label absolute RSS only as an upper bound.
- Future commands now bootstrap before verify, create `artifacts/results`, build with SwiftPM, run the resolved binary directly, collect `sw_vers`, Swift/Xcode versions, manifest checksums, probe hash, exact `stat -f %z` probe/model bytes and `otool -L` dependencies, with each long sample in a separate process and exit/no-residual checks. The runtime+model hard gate sums probe bytes plus every regular model file and compares the integer total with `524288000`; neither the whole `.build` directory nor `du -sh` is used.
- VAD model, version, license and SHA-256 are not frozen, not executed and not recorded.
- ADR-0002 remains Proposed and no G0 pass tag is issued.

## Deviations from plan

- Task 5's planned model download and audio benchmark were deferred by the user. The target corpus is not present, so no result, hash, transcript or accuracy value was fabricated.
- The execution status is `blocked` to represent the deferred G0 gate, not a passing implementation gate.

## Open risks

- SenseVoice suitability on the target Mac is unverified until the real corpus and model are authorized and available.
- No performance, memory, installed-size, truncation, resource-release or language-accuracy claim can be made.
- Integration hygiene found no tracked model, audio, DMG, credential or nested repository. Ignored SwiftPM caches and isolated worktrees are not release inputs.

## Rollback

Revert the commit containing this record and the linked ADR note. The probe and bootstrap inputs remain available at `e53776b`; no downloaded runtime/model artifact needs removal.
