# EXE-WP-00: Canonical repository foundation

- Plan: `docs/plans/2026-08-19-tsb-v0.1-master-plan.md`
- Owner: Sol
- Reviewer: Luna read-only repository and publication audits
- Status: passed
- Branch: `codex/repo-foundation`
- Commits: `94dbbe0`
- Started: 2026-08-19
- Finished: 2026-08-19

## Files changed

- Replaced the stale Assistant/Agent/Memory 0.1 documents with the approved local-dictation specification.
- Separated specs, plans, decisions, standards, execution records, evidence and references.
- Moved original product PDFs under `references/inputs`.
- Added repository exclusions for models, audio, DMGs, artifacts and signing material.
- Recorded the scope change in ADR-0001 and preserved the prior state on `archive/pre-v0.1-reframe-20260818`.

## Commands and results

- `git diff --cached --check`: passed with no whitespace errors.
- Placeholder and superseded-scope scan: no active plan/spec references to the former Agent/Memory runtime.
- Nested-repository scan: no `.git` below the canonical repository root.
- Staged-secret pattern scan: no common token or private-key pattern found.
- Staged-size gate: no new or modified file exceeds 5MB.
- Canonical repository size after organization: approximately 1.9MB.

## Acceptance criteria and evidence

- Evidence: `evidence/WP-00-AC-REPO-001-foundation.md`
- `docs/specs/tsb-v0.1-design.md` is the only active 0.1 design specification.
- Planning and actual execution use separate files and stable IDs.
- Product code is reserved for `apps/macos/TSB`; references cannot become accidental nested repositories.

## Deviations from plan

- The desktop repository and GitHub repository have unrelated existing histories. They were not force-merged during file organization.
- The machine does not have the `gh` CLI. Git publication can use standard `git`; GitHub metadata uses the authenticated GitHub connector or browser workflow.

## Open risks

- GitHub `main` currently contains only the earlier README history. It must be merged with `--allow-unrelated-histories` and reviewed before the first push.
- The Documents repository remains a separate safety copy and contains untracked reference clones and artifacts. It must not be bulk-copied or staged.

## Rollback

Switch to `archive/pre-v0.1-reframe-20260818` or revert commit `94dbbe0`. No source directory was deleted.
