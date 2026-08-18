# ADR-0002: Pin SenseVoiceSmall baseline inputs

- Status: Proposed
- Date: 2026-08-19
- Owners: GPT-5.5, Sol

## Context

TSB 0.1 needs a local ASR baseline before product transcription work starts. The G0 gate must prove the runtime, model files, license and checksums on the target Mac without committing downloaded weights or raw audio.

## Options

1. Probe several ASR models before choosing a baseline.
2. Use the pinned SenseVoiceSmall int8 model with the exact sherpa-onnx runtime already selected for WP-02.
3. Defer model pinning until product integration.

## Decision

Choose option 2 for the G0 candidate.

- Runtime: `sherpa-onnx 1.13.6`.
- Model source: `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2`.
- Local model directory: `artifacts/models/sensevoice-2024-07-17-int8/`.
- Required files: `model.int8.onnx`, `tokens.txt`, `LICENSE`, and generated `manifest.sha256`.
- Probe configuration: SenseVoice language `auto`, inverse text normalization enabled, CPU provider, greedy search.

The bootstrap script downloads to ignored local artifacts, validates the required model inputs and license, writes SHA-256 values, and refuses to overwrite an invalid existing target.

## Consequences

- Model weights, archives and generated checksums remain outside Git.
- Product work can consume a stable local path only after G0 accepts this ADR.
- A different model or runtime requires a later ADR rather than silently changing the bootstrap.

## Verification

This ADR can move to Accepted only after G0 evidence records:

- Mandarin, Cantonese and mixed Chinese-English decode without crash or truncation.
- 3-5 minute and 10 minute samples release all resources.
- Real-time factor is at most 0.5 on the target Mac.
- ASR active peak memory increase is at most 2GB.
- sherpa-onnx runtime plus model is at most 500MB.
- Runtime, model, license and SHA-256 values are recorded in evidence.
- VAD model, version, license and SHA-256 are recorded if selected; they are currently not frozen or executed for this gate.

Pending record: `evidence/WP-02-AC-ASR-001-sensevoice-probe.md` records the G0 gate as not run because local model/audio execution was explicitly deferred. Status remains Proposed; no G0 pass tag is issued.

## Rollback

Remove the local `artifacts/models/sensevoice-2024-07-17-int8/` directory and revert the bootstrap commit. Product code must not depend on this baseline until the G0 gate accepts it.
