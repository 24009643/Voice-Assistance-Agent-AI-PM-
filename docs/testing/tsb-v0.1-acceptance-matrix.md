# TSB 0.1 Acceptance Matrix

Status values: `not-entered`, `in-progress`, `passed`, `blocked`.

| ID | Requirement | Work package | Required evidence | Status |
|---|---|---|---|---|
| AC-001 | Toggle and push-to-talk start, stop and Escape cancellation are stable | WP-03, WP-04 | focused tests and 100-cycle summary | not-entered |
| AC-002 | Notch feedback appears within 200ms and stable segments appear without repeated jumping | WP-04, WP-05 | latency and UI-state evidence | not-entered |
| AC-003 | SenseVoice handles random Mandarin, Cantonese and mixed Chinese-English locally | WP-02, WP-07 | G0 and Golden Set reports | not-entered |
| AC-004 | 3–5 minute and 10 minute sessions are not truncated or lost | WP-04, WP-07 | long-session evidence | not-entered |
| AC-005 | Original, cleaned text and edit operations are separate and traceable | WP-03, WP-05 | storage/cleaner/UI tests | not-entered |
| AC-006 | Cleanup preserves protected numbers, entities, negations, order and meaning | WP-03, WP-07 | labeled cleaner regression report | not-entered |
| AC-007 | Each session auto-copies at most once; older completion cannot overwrite newer delivery | WP-03, WP-04 | idempotency and overlap tests | not-entered |
| AC-008 | New recording does not wait for old processing; primary and secondary cards do not cross sessions | WP-04, WP-05 | concurrency/UI evidence | not-entered |
| AC-009 | Future API profile Save/Cancel/Delete is safe and unused by dictation | WP-06 | Keychain failure tests and zero-network audit | not-entered |
| AC-010 | Retention, 24-hour failed audio and 2GB pruning work without early deletion | WP-06 | time/capacity/failure evidence | not-entered |
| AC-011 | Golden Set, performance, 100 cycles and 20 interruption cases pass | WP-07 | RC evidence index | not-entered |
| AC-012 | Runtime contains no LLM, voice wake, cloud ASR, simulated paste, Agent or knowledge base path | WP-01, WP-07 | architecture and network audit | not-entered |

No criterion is marked `passed` from an agent statement. The evidence file must name the tested commit, target environment, command and actual result.
