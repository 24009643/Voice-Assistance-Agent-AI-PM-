# WP-A2-03 Live Dual-ASR Integration Plan

> **Required workflow:** `superpowers:subagent-driven-development` and test-driven development.

**Goal:** Feed one live PCM stream to the WAV, UI level and Paraformer preview while preserving SenseVoice as the final local review.

**Spec:** `docs/specs/tsb-v0.1-alpha2-design.md` REQ-A2-003, REQ-A2-004, REQ-A2-005, REQ-A2-006 and REQ-A2-012. WP-A2-01 and WP-A2-02 gates must pass first.

## Task 1: Native PCM capture

- [ ] Add RED tests for hardware-format conversion to 16 kHz mono Float32, bounded chunk delivery, same-session WAV frames, stop/cancel/limit idempotency and resource release.
- [ ] Replace whole-file-only recording with `AVAudioEngine` tap plus `AVAudioConverter` and `AVAudioFile`. Emit near-200 ms chunks and never hold the entire PCM in memory.
- [ ] Keep the existing finished-audio value and session bundle path so the final SenseVoice path remains narrow.
- [ ] Run focused/full app tests and a clean build.
- [ ] Commit `feat(audio): stream PCM while recording`.

## Task 2: Product Paraformer adapter

- [ ] Add RED tests for model manifest validation, changed-only preview, ordered endpoint text, final tail, cancel/reset and initialization/decode degradation.
- [ ] Port the proven WP-A2-01 adapter into `Core/Transcription` with one actor owner and no extra protocol/factory.
- [ ] Add the model directory environment/development lookup using the same manifest convention as SenseVoice.
- [ ] Run focused/full app tests, both probes and clean build.
- [ ] Commit `feat(asr): add live Paraformer preview`.

## Task 3: Integrate preview, final and fallback

- [ ] Add RED coordinator tests proving partial updates are preview-only, SenseVoice wins, non-empty streaming fallback is used only on SenseVoice failure, copy remains once, and stale streaming events cannot cross sessions.
- [ ] Wire PCM chunks asynchronously to the Paraformer actor and publish changed preview on the main actor. Stop finalizes Paraformer and SenseVoice without blocking a new recording.
- [ ] Preserve the final source and both candidate texts in the bundle record.
- [ ] Run focused/full tests and both probes.
- [ ] Commit `feat(session): integrate live and reviewed ASR`.

## Task 4: Target-Mac acceptance

- [ ] Run Mandarin, Cantonese and random Chinese-English microphone samples, including sudden English terms such as Obsidian, Notion, GitHub and Codex.
- [ ] Run 3–5 minute, 10-minute, rapid start/stop/cancel and model-failure cases.
- [ ] Record first preview, refresh, stop-to-final, stop-to-copy, peak RSS and final-tail results in `EXE-WP-A2-03.md` and `evidence/WP-A2-03-LIVE-ASR.md`.
- [ ] Mark AC only from measured evidence; do not average away a failing language slice.
- [ ] Commit `docs(evidence): record live ASR gate`.
