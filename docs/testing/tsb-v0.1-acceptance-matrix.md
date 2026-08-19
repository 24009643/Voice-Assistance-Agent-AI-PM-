# TSB 0.1 Acceptance Matrix

Status values: `not-entered`, `in-progress`, `passed`, `blocked`, `superseded`.

| ID | Requirement | Work package | Required evidence | Status |
|---|---|---|---|---|
| AC-001 | Toggle and push-to-talk start, stop and Escape cancellation are stable | WP-03, WP-04 | focused tests and 100-cycle summary | superseded |
| AC-002 | Notch feedback appears within 200ms and stable segments appear without repeated jumping | WP-04, WP-05 | latency and UI-state evidence | superseded |
| AC-003 | SenseVoice handles random Mandarin, Cantonese and mixed Chinese-English locally | WP-02, WP-07 | G0 and Golden Set reports | superseded |
| AC-004 | 3–5 minute and 10 minute sessions are not truncated or lost | WP-04, WP-07 | long-session evidence | superseded |
| AC-005 | Original, cleaned text and edit operations are separate and traceable | WP-03, WP-05 | storage/cleaner/UI tests | superseded |
| AC-006 | Cleanup preserves protected numbers, entities, negations, order and meaning | WP-03, WP-07 | labeled cleaner regression report | superseded |
| AC-007 | Each session auto-copies at most once; older completion cannot overwrite newer delivery | WP-03, WP-04 | idempotency and overlap tests | superseded |
| AC-008 | New recording does not wait for old processing; primary and secondary cards do not cross sessions | WP-04, WP-05 | concurrency/UI evidence | superseded |
| AC-009 | Future API profile Save/Cancel/Delete is safe and unused by dictation | WP-06 | Keychain failure tests and zero-network audit | superseded |
| AC-010 | Retention, 24-hour failed audio and 2GB pruning work without early deletion | WP-06 | time/capacity/failure evidence | superseded |
| AC-011 | Golden Set, performance, 100 cycles and 20 interruption cases pass | WP-07 | RC evidence index | superseded |
| AC-012 | Runtime contains no LLM, voice wake, cloud ASR, simulated paste, Agent or knowledge base path | WP-01, WP-07 | architecture and network audit | superseded |

## Alpha 2 acceptance

| ID | Requirement | Work package | Required evidence | Status |
|---|---|---|---|---|
| AC-A2-001 | Every non-cancelled capture has one readable `audio.wav` + `record.json` bundle; cancel or confirmed user deletion removes only the selected bundle | WP-A2-02, WP-A2-04 | bundle round-trip, cancellation and user-deletion tests | not-entered |
| AC-A2-002 | Success/ASR failure/no-speech audio remains aligned; legacy flat records remain readable and untouched | WP-A2-02 | retention, legacy precedence and migration audit | not-entered |
| AC-A2-003 | One bounded PCM stream writes the WAV, updates level and feeds live ASR without a full memory copy | WP-A2-01, WP-A2-03 | PCM lifecycle, memory and long-session evidence | not-entered |
| AC-A2-004 | Paraformer draft is revisable preview only; SenseVoice final or explicit streaming fallback is ordered, sourced and copied once | WP-A2-01, WP-A2-03 | partial/final/fallback/late-event tests and language samples | not-entered |
| AC-A2-005 | Stop, Escape, device failure and 10-minute limit release every resource once and cannot cross sessions | WP-A2-02, WP-A2-03 | idempotency, interruption and resource evidence | not-entered |
| AC-A2-006 | Clipboard success is persisted truthfully and visibly confirmed within 100 ms for 1.2 s; failure never shows success | WP-A2-02 | delivery, UI-state, accessibility and stale-timer tests | not-entered |
| AC-A2-007 | Exact local terminology edits are deterministic, revisioned and traceable; unmatched similar text is unchanged | WP-A2-04 | term CRUD, alias and edit-operation tests | not-entered |
| AC-A2-008 | Private SessionBundles stay local/Git-ignored and are used only for evaluation/regression | WP-A2-04 | ignore, logging, network and purpose-manifest audit | not-entered |
| AC-A2-009 | Manual export rejects unreviewed entries and requires selection/preview/confirmation; public audio has a separate confirmation and no automatic publication | WP-A2-04 | review gate, package content and no-network audit | not-entered |
| AC-A2-010 | API profiles are secure; optional review is explicit text-only, independently saved and never changes clipboard automatically | WP-A2-04 | Keychain, DTO, consent, timeout/error and clipboard tests | not-entered |
| AC-A2-011 | Runtime contains no training, training-data generation, cloud ASR/audio upload, voice wake or simulated paste path | WP-A2-04, WP-A2-05 | source/dependency/network/permission audit | not-entered |
| AC-A2-012 | Target-Mac P95: first live update <=800 ms, stop-to-final <=1.5 s, stop-to-copy <=2 s; no case exceeds 3 s in the acceptance set | WP-A2-01, WP-A2-03, WP-A2-05 | per-language timing, RTF and memory report | not-entered |

Superseded rows remain as history and cannot pass or fail Alpha 2. No criterion is marked `passed` from an agent statement. The evidence file must name the tested commit, target environment, command and actual result.
