# WP-00 / AC-REPO-001 Repository foundation evidence

- Date: 2026-08-19
- Device: target developer Mac
- Branch: `codex/repo-foundation`
- Tested commit: `94dbbe0`

## Expected

- One canonical repository at `/Users/zhuohengchi/Desktop/The Second Brain`.
- Current local-only 0.1 scope is the active source of truth.
- Specs, plans, execution records and evidence have separate paths.
- No nested Git repository, downloaded model, DMG, raw audio or secret enters the staged tree.
- Former desktop documents remain recoverable through Git.

## Actual

- Canonical repository is approximately 1.9MB.
- Active Markdown entry points are under `docs/`, `evidence/` and `references/`.
- No `.git` directory exists below the repository root.
- Both original PDFs are under `references/inputs`; neither exceeds 5MB.
- The previous desktop state is reachable through branch `archive/pre-v0.1-reframe-20260818`.
- The separate Documents working directory was not changed or removed.

## Reproduction

```bash
git status --short
git show --check --stat 94dbbe0
find . -mindepth 2 -name .git -print
rg --files README.md docs evidence references | sort
du -sh .
```

## Result

Passed for the local repository-foundation gate. Remote-history reconciliation is tracked under WP-08 publication work.
