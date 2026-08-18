# EXE-WP-02: Deferred SenseVoice G0 gate

- Plan: `docs/plans/2026-08-19-g0-foundation-and-sensevoice-probe.md`
- Owner: GPT-5.5
- Reviewer: Sol
- Status: blocked
- Branch: `codex/wp-02-sensevoice`
- Commits: `b62b7c7` (probe), `e53776b` (bootstrap and ADR); this record is the sanitized gate record
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
- Real model bootstrap, `--verify-only`, audio decode and G0 benchmark commands: not run by explicit user ruling.

## Acceptance criteria and evidence

- Evidence: `evidence/WP-02-AC-ASR-001-sensevoice-probe.md`.
- Tooling checks pass, but G0 is **not run**.
- Real decode, RTF, active memory delta, installed-size, truncation/resource-release and language-accuracy gates remain unmeasured.
- Absolute process peak RSS is not treated as active ASR memory delta; a future run requires a pre-load baseline or must label absolute RSS only as an upper bound.
- ADR-0002 remains Proposed and no G0 pass tag is issued.

## Deviations from plan

- Task 5's planned model download and audio benchmark were deferred by the user. The target corpus is not present, so no result, hash, transcript or accuracy value was fabricated.
- The execution status is `blocked` to represent the deferred G0 gate, not a passing implementation gate.

## Open risks

- SenseVoice suitability on the target Mac is unverified until the real corpus and model are authorized and available.
- No performance, memory, installed-size, truncation, resource-release or language-accuracy claim can be made.

## Rollback

Revert the commit containing this record and the linked ADR note. The probe and bootstrap inputs remain available at `e53776b`; no downloaded runtime/model artifact needs removal.
