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
- [Alpha 2 canonical design](specs/tsb-v0.1-alpha2-design.md) — active requirements and exclusions.
- [Alpha 2 master plan](plans/2026-08-19-tsb-v0.1-alpha2-master-plan.md) — work packages, gates and traceability.
- [ADR-0004](decisions/ADR-0004-alpha2-adaptive-dictation.md) — dual local ASR, retained bundles, controlled export and text-only review boundary.

Agent work is additionally governed by `standards/weekly-budget-guard.md`.
