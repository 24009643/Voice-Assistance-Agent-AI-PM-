# EXE-WP-02: SenseVoice G0 foundation and partial smoke

- Plan: `docs/plans/2026-08-19-g0-foundation-and-sensevoice-probe.md`
- Owner: GPT-5.5 probe/bootstrap, Luna evidence, Sol integration
- Reviewer: independent Sol reviewers
- Status: partial smoke recorded; G0 not passed
- Branch: `codex/wp-02-g0-run`
- Evidence: `evidence/WP-02-AC-ASR-001-sensevoice-probe.md`
- Started: 2026-08-19
- Updated: 2026-08-19

## Files changed

- Added the SenseVoice G0 evidence record.
- Added this execution record.
- Linked the pending evidence in `docs/decisions/ADR-0002-sensevoice-baseline.md`; ADR status remains Proposed.
- Recorded the first real official-short-sample smoke without committing model weights, audio, raw transcripts or generated result files.

## Commands and results

- `sh -n scripts/bootstrap-sensevoice-model.sh`: passed, exit 0.
- `scripts/bootstrap-sensevoice-model.sh --self-check`: passed, exit 0.
- `swift test --package-path probes/sensevoice`: passed, 5 tests and 0 failures.
- `swift run --package-path probes/sensevoice SenseVoiceProbe --help`: passed, exit 0; usage printed without model files.
- Earlier integration rerun at `f2b7c3e`: macOS app checks passed, 8 tests and 0 failures; probe package tests passed, 5 tests and 0 failures.
- `scripts/bootstrap-sensevoice-model.sh`: passed; downloaded the pinned official model archive into ignored `artifacts/models/`.
- `scripts/bootstrap-sensevoice-model.sh --verify-only`: passed.
- `swift build --package-path probes/sensevoice -c release`: passed.
- `/usr/bin/time -l SenseVoiceProbe --model-dir artifacts/models/sensevoice-2024-07-17-int8 --manifest artifacts/fixtures/g0-official-short.jsonl`: passed; 5 official short samples decoded, exit 0, no residual process.
- `git diff --check`: passed.
- `git status --ignored --short`: checked; model, sample audio, manifest, build outputs and raw results appear only under ignored paths.

## Partial smoke summary

- Official short sample source: k2-fsa `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2`, archive members `test_wavs/en.wav`, `ja.wav`, `ko.wav`, `yue.wav`, `zh.wav`.
- All five samples were valid RIFF/WAVE PCM, 16-bit, mono, 16 kHz.
- Recognizer settings: `language=auto`, `useITN=true`, CPU provider, greedy search.
- Cold load: `392` ms.
- Per-sample RTF range: `0.026250` to `0.027964`.
- Absolute process peak RSS: `907821056` bytes. This is not an ASR active-memory delta.
- Probe executable plus all model-directory regular files: `279588828` bytes.
- Conservative total including SwiftPM-copied static archives plus all model-directory regular files: `419494772` bytes.
- `otool -L` for the release probe reported no non-system dynamic dependencies.

## Still not G0

The required user corpus is absent: Mandarin, Cantonese, mixed Chinese-English, three 3-5 minute samples and one 10 minute sample. Long-audio resource release, truncation and target-corpus accuracy remain unmeasured. VAD model/version/license/SHA-256 are not selected or executed.

ADR-0002 remains `Proposed`; no G0 pass tag is issued; WP-03 must not begin.

## Rollback

Revert the commit containing this record and the linked ADR/evidence updates. Remove local ignored `artifacts/models/`, `artifacts/fixtures/` and `artifacts/results/` if the downloaded model, copied audio or raw outputs are no longer needed.
