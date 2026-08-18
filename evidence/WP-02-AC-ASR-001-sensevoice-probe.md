# WP-02 / AC-ASR-001 SenseVoice G0 gate evidence

- Date: 2026-08-19
- Device: target Mac, Apple M5 Pro, arm64, 48 GiB memory
- Branch: `codex/wp-02-sensevoice`
- Tested commit: `e53776b`
- Gate result: **Not run (deferred)**

## Expected

- The pinned sherpa-onnx 1.13.6 and SenseVoiceSmall int8 candidate decode Mandarin, Cantonese and mixed Chinese-English samples without crash or truncation.
- Three-to-five-minute and ten-minute samples complete and release resources.
- Real-time factor is at most 0.5; ASR active peak memory increase is at most 2 GiB; runtime plus model is at most 500 MB.
- Runtime, model, license and SHA-256 values are recorded without committing model weights, audio or raw output.

## Scope ruling

The user explicitly deferred local runtime execution for this task. The real model was not downloaded, no audio was decoded, and the Mandarin, Cantonese, mixed Chinese-English, three-to-five-minute and ten-minute target-Mac corpus is not present. G0 is therefore recorded as **not run**, never Passed.

## Tooling and non-model checks

Task 3 established the probe at `b62b7c7` (`fix(probe): measure duration from decoded WAV`), with the exact sherpa-onnx package dependency at 1.13.6. Its reported checks were 5 manifest tests passing and `SenseVoiceProbe --help` exiting 0 without model files.

Task 4 established the bootstrap and ADR proposal at `e53776b` (`fix(asr): preserve dangling model target symlink`). Its reported checks were shell syntax passing, the bootstrap self-check passing, the probe package tests passing (5 tests, 0 failures), and the model path remaining ignored. ADR-0002 remains Proposed.

The permitted checks were rerun at `e53776b`:

```text
sh -n scripts/bootstrap-sensevoice-model.sh                 exit 0
scripts/bootstrap-sensevoice-model.sh --self-check          exit 0; self-check passed
swift test --package-path probes/sensevoice                 exit 0; 5 tests, 0 failures
swift run --package-path probes/sensevoice SenseVoiceProbe --help
                                                            exit 0; usage printed, no model required
```

## Deferred hard gates

The following values are intentionally unexecuted and unreported:

- Real decode: not run.
- RTF: not measured.
- Active ASR memory delta: not measured.
- Runtime plus model installed size: not measured; no model/runtime artifact size is claimed.
- Truncation and resource release for three-to-five-minute and ten-minute samples: not observed.
- Mandarin, Cantonese and mixed Chinese-English language accuracy observations: not made.
- Model, runtime, license and SHA-256 evidence: not recorded because no real model was downloaded.

The current probe's `peakRSSBytes` is an absolute process peak RSS, not an active ASR memory delta. A future G0 run must measure a pre-load baseline and report the delta; otherwise absolute RSS may be reported only as an upper bound, not as proof of the 2 GiB active-memory gate.

## Future reproduction commands

These commands are recorded for the authorized future run and were **not run for this record**:

```bash
scripts/bootstrap-sensevoice-model.sh --verify-only

swift run --package-path probes/sensevoice SenseVoiceProbe \
  --model-dir artifacts/models/sensevoice-2024-07-17-int8 \
  --manifest artifacts/fixtures/g0-short.jsonl \
  > artifacts/results/g0-short.json

swift run --package-path probes/sensevoice SenseVoiceProbe \
  --model-dir artifacts/models/sensevoice-2024-07-17-int8 \
  --manifest artifacts/fixtures/g0-target.jsonl \
  > artifacts/results/g0-target.json
```

`g0-target.jsonl` must be the target-Mac manifest containing Mandarin, Cantonese, mixed Chinese-English, three-to-five-minute and ten-minute WAV samples. The future report must add the model/runtime/license SHA-256 values, pre-load memory baseline and delta, RTF, installed-size measurement, truncation/resource-release observations and per-language accuracy observations. It must not copy model weights, audio or raw transcripts into Git.

## Hygiene result

- `artifacts/` is absent in this worktree; no model, audio or generated result exists.
- `git check-ignore --no-index -v` confirms the future model, fixture and result paths are ignored by `artifacts/`.
- No tracked model, audio, raw transcript or generated artifact is present.

## Result

The non-model tooling is reproducible, but the G0 acceptance gate is **not run**. ADR-0002 remains `Proposed`; no G0 pass tag is authorized.
