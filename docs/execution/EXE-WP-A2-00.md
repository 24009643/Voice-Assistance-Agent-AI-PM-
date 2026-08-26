# EXE-WP-A2-00: Alpha 2 design freeze

- Date: 2026-08-19
- Branch: `codex/wp-04-alpha2`
- Base: `584a7b1`
- Worktree: `$HOME/Desktop/The Second Brain/.worktrees/wp-04-alpha2`
- Status: passed

## Outcome

Alpha 2 now has one active decision, one canonical design, one master plan, four executable work-package plans and a supersession-aware acceptance matrix. Historical 0.1 documents remain in Git but are visibly marked as non-authoritative where they conflict.

Three independent read-only audits covered document conflicts, the current session/audio/clipboard/UI chain, and the sherpa-onnx 1.13.6 Streaming Paraformer Swift API. Their findings were resolved into ADR-0004 and the active design before any Alpha 2 production code changed.

## Traceability

| WP | ADR | REQ | Production files | Focused check | AC | Evidence | Commit |
|---|---|---|---|---|---|---|---|
| WP-A2-00 | ADR-0004 | REQ-A2-001 through REQ-A2-012 | none; docs only | active-doc conflict and placeholder scan | AC-A2-001 through AC-A2-012 defined, not entered | `evidence/WP-A2-00-DESIGN-FREEZE.md` | recorded by this WP commit |

## Decisions recorded

- Keep SenseVoice as authoritative local final; add Streaming Paraformer only as live draft and explicit fallback.
- Retain one aligned SessionBundle for every non-cancelled capture; do not auto-migrate legacy files.
- Reuse the installed sherpa-onnx dependency; do not add dynamic Paraformer hotword claims.
- Use exact local terminology edits with provenance.
- Treat retained bundles as the private corpus; export is manual, reviewed and never automatically published.
- Allow optional explicit text-only LLM review, but no training, training-data generation or audio network path.
- Preserve local stop-to-copy as the non-blocking product outcome.

## Verification

```text
git diff --check
! rg "TODO|TBD|待定|稍后补" <Alpha 2 authoritative documents>
! rg "成功音频.*删除|不调用 LLM|API.*永不读取|真正.*流式.*不" <Alpha 2 authoritative documents>
```

Result: `alpha2-doc-consistency: PASS`.

The isolated-worktree baseline before this documentation change was macOS app 48/48 tests and SenseVoice probe 7/7 tests. Production source did not change in WP-A2-00.

## Weekly guard

The Codex account Weekly percentage is not exposed to shell/tools, and Computer Use is explicitly prohibited from inspecting the Codex app. No percentage is fabricated. The user-visible UI remains the source of truth; execution stops before a new WP when it shows 55% remaining or lower.
