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
