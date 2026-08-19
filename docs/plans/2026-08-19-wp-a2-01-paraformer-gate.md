# WP-A2-01 Streaming Paraformer Gate Plan

> **Required workflow:** `superpowers:subagent-driven-development` and test-driven development.

**Goal:** Prove the pinned sherpa-onnx online Paraformer path on macOS before product integration.

**Spec:** `docs/specs/tsb-v0.1-alpha2-design.md` REQ-A2-003, REQ-A2-004, REQ-A2-005, REQ-A2-012.

**Files owned:** `probes/paraformer/`, `scripts/bootstrap-paraformer-model.sh`, `docs/execution/EXE-WP-A2-01.md`, `evidence/WP-A2-01-PARAFORMER.md`. Do not modify the app coordinator or UI.

## Task 1: Freeze and validate the model bundle

- [ ] Add probe tests that fail when encoder, decoder, tokens, license or manifest is missing/mismatched.
- [ ] Implement the smallest model-location and SHA-256 validator, reusing the SenseVoice manifest format.
- [ ] Add a safe bootstrap script for `sherpa-onnx-streaming-paraformer-trilingual-zh-cantonese-en`; reject non-empty destinations unless explicitly confirmed and never write into Git-tracked paths.
- [ ] Run focused tests, `swift test --package-path probes/paraformer`, and `git diff --check`.
- [ ] Commit `feat(probe): validate streaming Paraformer model`.

## Task 2: Exercise the actual Swift online recognizer

- [ ] Add RED tests for ordered partial changes, endpoint reset, final tail, cancel/reset and empty input.
- [ ] Implement one recognizer owner using sherpa-onnx 1.13.6: normalized Float32 input, greedy search, 16 kHz/80 features, 0.2-second tail padding, `inputFinished`, and no hotword arguments.
- [ ] Add a CLI that reads a 16 kHz mono WAV incrementally near 200 ms and emits JSONL timing/result events without logging audio samples.
- [ ] Run focused/full probe tests and one real Mandarin/Cantonese/Chinese-English sample per slice.
- [ ] Commit `feat(probe): exercise online Paraformer`.

## Task 3: Record G-A2-ASR evidence

- [ ] Run cold and warm model load, first changed text, refresh interval, total RTF, final tail, cancellation and peak RSS on the target Mac.
- [ ] Record exact sherpa/model versions, model/license URLs, file hashes, commands, results and limitations in `EXE-WP-A2-01.md` and `evidence/WP-A2-01-PARAFORMER.md`.
- [ ] Mark AC-A2-003, AC-A2-004 and AC-A2-012 only from the tested commit; a failed threshold remains explicit and blocks WP-A2-03.
- [ ] Run all probe tests, the existing SenseVoice probe, `git diff --check`, staged-path and secret/binary checks.
- [ ] Commit `docs(evidence): record Paraformer gate`.
