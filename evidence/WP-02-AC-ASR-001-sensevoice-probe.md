# WP-02 / AC-ASR-001 SenseVoice G0 gate evidence

- Date: 2026-08-19
- Device: target Mac, Apple M5 Pro, arm64, 48 GiB memory (`51539607552` bytes)
- Branch: `codex/wp-02-g0-run`
- Tested commit before this evidence update: `f2b7c3e`
- Gate result: **Partial smoke only; G0 not passed**

## Expected

- The pinned sherpa-onnx 1.13.6 and SenseVoiceSmall int8 candidate decode Mandarin, Cantonese and mixed Chinese-English samples without crash or truncation.
- Three-to-five-minute and ten-minute samples complete and release resources.
- Real-time factor is at most 0.5; ASR active peak memory increase is at most 2 GiB; runtime plus model is at most 500 MB.
- Runtime, model, license and SHA-256 values are recorded without committing model weights, audio or raw output.

## Scope ruling

The real pinned model was downloaded and verified, and the existing probe decoded the official short sample WAV files packaged by k2-fsa with the pinned model archive. This is only a smoke run. The required user corpus is still absent: Mandarin, Cantonese, mixed Chinese-English, three 3-5 minute samples and one 10 minute sample. G0 therefore remains **not passed**, ADR-0002 remains `Proposed`, no pass tag is authorized and WP-03 must not begin.

Raw probe JSON, raw transcripts, audio and model files are stored only under ignored `artifacts/`.

## Official sample source

- Documentation: `https://k2-fsa.github.io/sherpa/onnx/sense-voice/pretrained.html`
- Release archive: `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2`
- Archive members copied to ignored fixtures: `test_wavs/en.wav`, `test_wavs/ja.wav`, `test_wavs/ko.wav`, `test_wavs/yue.wav`, `test_wavs/zh.wav`.

All five copied WAV files were valid RIFF/WAVE PCM, 16-bit, mono, 16 kHz.

## Model and runtime

- sherpa-onnx SwiftPM dependency: version `1.13.6`, revision `1cb484af5e69d3c7803c1eb0b3b5ab8041e0e911`.
- onnxruntime-libs SwiftPM dependency: version `1.27.1`, revision `1fbef5f2a1b5c2691fe9411243f3a8afe9a0b169`.
- Recognizer settings: `language=auto`, `useITN=true`, CPU provider, greedy search.
- Model directory: `artifacts/models/sensevoice-2024-07-17-int8/`.
- Model manifest SHA-256: `311ab4b34975ba648d3d64a5a1e70bda61ca464573b8829bd5ae7c4c6beefa8e`.
- `model.int8.onnx`: `239233841` bytes, SHA-256 `c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51`.
- `tokens.txt`: `315894` bytes, SHA-256 `f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc`.
- `LICENSE`: `71` bytes, SHA-256 `221c6df10b0931a5629adad671ea48fb7747e034c414b6d2bfa275bc3dd4ea17`.
- Release probe executable: `39082160` bytes, SHA-256 `57313ba9d45e75be02268685bc3c6ed9604d8239991943359a2c321b6ad4efe8`.
- `otool -L` for the release probe reported no non-system dynamic dependencies.
- Probe executable plus all model-directory regular files: `279588828` bytes.
- Conservative total including SwiftPM-copied static archives plus all model-directory regular files: `419494772` bytes.

## Smoke measurements

Raw output: `artifacts/results/g0-official-short.jsonl`, SHA-256 `774ac69f2022bf28ac53b39c6662fa0508f75f89da5abcef6f4a34cb48e69fbb`.

Timing stderr: `artifacts/results/g0-official-short.time.txt`, SHA-256 `a870324e6a8b9ea7414951d2499aaa5c1eee398fb8a8789952ef91ebb0d64919`.

| Sample | Expected language | Detected language | Duration seconds | Latency ms | RTF |
| --- | --- | --- | ---: | ---: | ---: |
| `sensevoice-official-en` | `en` | `<|en|>` | 7.152 | 200 | 0.027964 |
| `sensevoice-official-ja` | `ja` | `<|ja|>` | 7.200 | 189 | 0.026250 |
| `sensevoice-official-ko` | `ko` | `<|ko|>` | 4.608 | 126 | 0.027344 |
| `sensevoice-official-yue` | `yue` | `<|yue|>` | 5.148 | 138 | 0.026807 |
| `sensevoice-official-zh` | `zh` | `<|zh|>` | 5.592 | 151 | 0.027003 |

- Probe exit: `0`.
- Residual `SenseVoiceProbe` process after run: none.
- Cold load: `392` ms.
- Total elapsed inside probe: `1204` ms.
- `/usr/bin/time -l` elapsed: `1.23 real`, `1.12 user`, `0.09 sys`.
- Absolute process peak RSS: `907821056` bytes, matching the probe JSON and `/usr/bin/time -l`.

The peak RSS value is absolute process peak RSS, not an ASR active-memory delta. Because the absolute peak is below `2147483648` bytes, the active delta for this short-process smoke cannot exceed 2 GiB, but this is still not a target-corpus G0 pass.

## Commands and results

```text
scripts/bootstrap-sensevoice-model.sh
result: passed; bootstrapped the pinned official model.

scripts/bootstrap-sensevoice-model.sh --verify-only
result: passed.

swift test --package-path probes/sensevoice
result: passed; 5 tests, 0 failures.

swift build --package-path probes/sensevoice -c release
result: passed.

/usr/bin/time -l SenseVoiceProbe --model-dir artifacts/models/sensevoice-2024-07-17-int8 --manifest artifacts/fixtures/g0-official-short.jsonl
result: passed; 5 official short samples decoded, exit 0, no residual process.
```

Toolchain snapshot:

```text
macOS 26.5.2 (25F84)
Apple Swift 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
Xcode 26.6 (17F113)
```

## Remaining hard gates

- Required user Mandarin sample: absent.
- Required user Cantonese sample: absent.
- Required user mixed Chinese-English sample: absent.
- Three required 3-5 minute samples: absent.
- Required 10 minute sample: absent.
- Long-audio resource release: unmeasured.
- Target-corpus truncation and accuracy observations: unmeasured.
- VAD model/version/license/SHA-256: not selected, frozen or executed.

## Hygiene result

- `artifacts/` is ignored and contains the downloaded model, copied official sample audio, ignored manifest and raw result files.
- `git status --ignored --short` was checked before editing tracked evidence and showed `artifacts/` only as ignored.
- No model, audio, raw transcript or generated result is intended for commit.

## Result

The first real SenseVoice smoke on official short samples succeeded, but the G0 acceptance gate remains **not passed** because the required user corpus and long-audio evidence are missing. ADR-0002 remains `Proposed`; no G0 pass tag is authorized.
