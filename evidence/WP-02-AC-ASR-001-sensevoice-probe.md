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

Current toolchain snapshot (read-only commands, not a G0 runtime run):

```text
sw_vers
ProductVersion: 26.5.2
BuildVersion: 25F84
swift --version
Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
xcodebuild -version
Xcode 26.6
Build version 17F113
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
- VAD model, version, license and SHA-256: not frozen, not executed and not recorded.

The current probe's `peakRSSBytes` is an absolute process peak RSS, not an active ASR memory delta. A future G0 run must measure a pre-load baseline and report the delta; otherwise absolute RSS may be reported only as an upper bound, not as proof of the 2 GiB active-memory gate.

## Future reproduction commands

These commands are recorded for the authorized future run and were **not run for this record**. They are ordered so a clean worktree can bootstrap the ignored model, verify it, create the result directory, build the probe, and run the binary directly:

```bash
MODEL_DIR=artifacts/models/sensevoice-2024-07-17-int8
RESULT_DIR=artifacts/results

# Requires explicit authorization for the real model download.
scripts/bootstrap-sensevoice-model.sh --target "$MODEL_DIR"
scripts/bootstrap-sensevoice-model.sh --verify-only --target "$MODEL_DIR"
(cd "$MODEL_DIR" && shasum -a 256 -c manifest.sha256)
mkdir -p "$RESULT_DIR"

swift build --package-path probes/sensevoice --configuration release
BUILD_DIR="$(swift build --package-path probes/sensevoice --configuration release --show-bin-path)"
PROBE_BIN="$BUILD_DIR/SenseVoiceProbe"
test -x "$PROBE_BIN"

/usr/bin/time -l "$PROBE_BIN" \
  --model-dir "$MODEL_DIR" \
  --manifest artifacts/fixtures/g0-short.jsonl \
  > "$RESULT_DIR/g0-short.json" \
  2> "$RESULT_DIR/g0-short.time.txt"
test "$?" -eq 0
if pgrep -x SenseVoiceProbe >/dev/null; then exit 1; fi
```

For the target corpus, `g0-target.jsonl` must contain Mandarin, Cantonese, mixed Chinese-English, three-to-five-minute and ten-minute WAV samples. Each long sample must be represented by a one-sample manifest and run as its own process; these are exact future invocations, not executed now:

```bash
run_one() {
  manifest="$1"
  output="$2"
  /usr/bin/time -l "$PROBE_BIN" \
    --model-dir "$MODEL_DIR" \
    --manifest "$manifest" \
    > "$RESULT_DIR/$output.json" \
    2> "$RESULT_DIR/$output.time.txt"
  status=$?
  test "$status" -eq 0
  if pgrep -x SenseVoiceProbe >/dev/null; then exit 1; fi
}

run_one artifacts/fixtures/mandarin-3-5.jsonl mandarin-3-5
run_one artifacts/fixtures/cantonese-3-5.jsonl cantonese-3-5
run_one artifacts/fixtures/mixed-zh-en-3-5.jsonl mixed-zh-en-3-5
run_one artifacts/fixtures/ten-minute.jsonl ten-minute
```

Collect the environment, model manifest/hash, actual probe/runtime deliverable size and dynamic dependencies without committing them:

```bash
sw_vers
swift --version
xcodebuild -version
(cd "$MODEL_DIR" && shasum -a 256 -c manifest.sha256)
(cd "$MODEL_DIR" && shasum -a 256 manifest.sha256)
du -sh "$MODEL_DIR" "$PROBE_BIN" "$BUILD_DIR"
otool -L "$PROBE_BIN"
```

The JSON `peakRSSBytes` and each `*.time.txt` maximum-resident-set-size line are absolute process peak RSS, not active ASR memory delta. Record the absolute value in bytes. If an absolute value is at most `2147483648`, it is a conservative upper bound proving the active delta cannot exceed 2 GiB for that process, but it is still not by itself a G0 pass. If it exceeds 2 GiB, add pre-load RSS instrumentation to the probe before measuring or claiming the active delta; never call that run Passed. Compute RTF from each sample's `latencyMilliseconds` and `audioDurationSeconds`. Check every process exit and absence of a residual `SenseVoiceProbe` process before interpreting any result.

The future report must add model/runtime/license SHA-256 values, VAD model/version/license/hash if selected, the memory interpretation, RTF, installed-size measurement, truncation/resource-release observations and per-language accuracy observations. It must not copy model weights, audio or raw transcripts into Git.

## Hygiene result

- `artifacts/` is absent in this worktree; no model, audio or generated result exists.
- `git check-ignore --no-index -v` confirms the future model, fixture and result paths are ignored by `artifacts/`.
- No tracked model, audio, raw transcript or generated artifact is present.

## Result

The non-model tooling is reproducible, but the G0 acceptance gate is **not run**. ADR-0002 remains `Proposed`; no G0 pass tag is authorized.
