# Documentation Map

| Directory | Purpose | Change rule |
|---|---|---|
| `specs/` | Approved product and technical truth | Change only after product review |
| `plans/` | Future-tense implementation steps and task ownership | Freeze before execution; deviations go to execution records |
| `decisions/` | Accepted or superseded architecture decisions | Append a new ADR; do not rewrite accepted history |
| `standards/` | Repository-wide engineering and privacy rules | Applies to every task and agent |
| `execution/` | Actual commits, commands, evidence links and deviations | Append during execution; never use as a product spec |

Search anchors use stable IDs:

- Requirements: `REQ-xxx`
- Architecture decisions: `ADR-xxxx`
- Work packages: `WP-xx`
- Acceptance criteria: `AC-xxx`
- Execution records: `EXE-xx`

Each execution record links one work package, its commits, acceptance criteria and evidence paths. This provides traceability without introducing a separate project-management system.

## Current execution and evidence

- [WP-03 Alpha local dictation execution record](execution/EXE-WP-03.md) — gate is pending until a user performs the real microphone-to-clipboard smoke.
- [WP-03 Alpha local-chain evidence](../evidence/WP-03-ALPHA-local-chain.md) — automated verification and the shortest manual acceptance path.

Agent work is additionally governed by `standards/weekly-budget-guard.md`.
