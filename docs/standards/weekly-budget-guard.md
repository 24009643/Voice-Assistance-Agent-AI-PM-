# Codex Weekly Budget Guard

- Effective date: 2026-08-19
- Source of truth: Codex Settings → Analytics → Usage
- User red line: 50% weekly allowance remaining
- Operational stop line: 55% remaining

The 5-point buffer covers delayed dashboard refresh and calls already in flight. It is the only defensible way to preserve at least 50%; stopping when the page first displays 50% can already be too late.

## Checkpoints

Sol reads the authenticated Usage page directly:

1. before starting any work package;
2. before spawning an implementation or review agent;
3. after every agent completes;
4. before a long build, benchmark, publication or external tool sequence;
5. at least every 10 minutes while an unusually long task is still running.

Only one implementation agent may run at a time. No permanent quota-monitor agent is used because it consumes the same allowance and cannot enforce an account-level stop more reliably than the orchestrator.

## Stop protocol

When displayed weekly remaining allowance is 55% or lower:

1. do not start another task, agent, review, build or publication;
2. interrupt running subagents at the next safe message boundary;
3. preserve already completed files and commits without attempting unfinished feature work;
4. create `docs/execution/STOP-WEEKLY-BUDGET-YYYY-MM-DD.md` containing the observed percentage and reset time, branch and HEAD, completed work, verification already obtained, incomplete work, risks and the exact resume command;
5. commit only that handoff report if the worktree is in a safe committable state, then end the task.

No report may claim unfinished tests or features passed. Work resumes only after the user confirms the new Usage reading is above the operational stop line.

## Limitation

Codex task tools do not expose the account-level weekly percentage. The guard depends on the authenticated web dashboard and is checked at the checkpoints above; it is not a continuous atomic quota lock.
