# Execution Records

Current Alpha 2 execution starts with [`EXE-WP-A2-00.md`](EXE-WP-A2-00.md).
Each Alpha 2 record owns the single live
`WP -> ADR -> REQ -> files -> tests -> AC -> evidence -> commit` mapping for its
work package.

Plans are frozen intent. Execution records are append-only accounts of what actually happened.

One file is created per work package: `EXE-WP-xx.md`.

Required fields:

```markdown
# EXE-WP-xx: title

- Plan: docs/plans/...
- Owner:
- Reviewer:
- Status: not-started | in-progress | passed | blocked
- Branch:
- Commits:
- Started:
- Finished:

## Files changed
## Commands and results
## Acceptance criteria and evidence
## Deviations from plan
## Open risks
## Rollback
```

Raw build logs, recordings and generated reports stay in ignored `artifacts/` or `evidence/raw/`. The execution record stores only a reproducible command, outcome, small relevant excerpt and SHA-256 when needed.
