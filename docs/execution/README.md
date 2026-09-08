# Execution Records

Repository-hygiene execution is recorded in
[`EXE-WP-HYGIENE.md`](EXE-WP-HYGIENE.md), including verification, review
follow-ups and integration references.

Current Alpha 2 execution starts with [`EXE-WP-A2-00.md`](EXE-WP-A2-00.md) and
continues through [`EXE-WP-A2-01.md`](EXE-WP-A2-01.md) and
[`EXE-WP-A2-02.md`](EXE-WP-A2-02.md). A2-01 and A2-02 pass bounded technical
gates only; their product acceptance criteria remain in progress.
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
