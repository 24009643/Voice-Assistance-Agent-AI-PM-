# WP-A2-01: Online Paraformer probe evidence

- Tested commit: `8f4b8ed` (Paraformer probe code: `c491cb5`)
- Build: `swift build -c release --package-path probes/paraformer`
- Runtime: sherpa-onnx Swift wrapper 1.13.6; CPU, one thread, greedy decode;
  16 kHz / 80-bin input; no dynamic-hotword fields
- Scope: public G0 WAV release-probe evidence on the target Apple-silicon Mac.
  No audio, models, raw JSONL or transcripts are tracked in this repository.

## Model provenance and integrity

| Item | Recorded value |
|---|---|
| Model | `sherpa-onnx-streaming-paraformer-trilingual-zh-cantonese-en` |
| Release archive | [official sherpa-onnx model release](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-paraformer-trilingual-zh-cantonese-en.tar.bz2) |
| Archive SHA-256 | `d479167d8752628d9032d29de1060493865389d1e295a1c2e8e011e7062f1932` |
| Source card revision | [`e4a00371f24b40f5cd477643edffa7ee55f9f532`](https://www.modelscope.cn/models/dengcunqin/speech_paraformer-large_asr_nat-zh-cantonese-en-16k-vocab8501-online/files?version=e4a00371f24b40f5cd477643edffa7ee55f9f532) |
| License | [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0.txt), SHA-256 `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| `encoder.int8.onnx` SHA-256 | `6047a644b41b236d9d8e89e3b94ef39d1b7037daab028131b722ca52e10b0357` |
| `decoder.int8.onnx` SHA-256 | `545427acf508452b7d89969be082c8128c681e3432ff43aef09f6159f4b61a7e` |
| `tokens.txt` SHA-256 | `45b31504211675dd52aa88f998a6f6161703a2834e86760c1cda645a22538085` |

The installed manifest and canonical license passed bootstrap verification.
The Swift package pins sherpa-onnx 1.13.6 at
`1cb484af5e69d3c7803c1eb0b3b5ab8041e0e911` (with onnxruntime 1.27.1).

## Release-probe measurements

The public G0 Mandarin, Cantonese and Chinese-English fixtures were read as
200 ms normalized `Float32` chunks. `RTF` is release-process wall time divided
by WAV duration; RSS is the maximum resident set reported by the measurement.

| Slice | Duration | Partial / final events | Finish | Max chunk | RTF | Peak RSS |
|---|---:|---:|---:|---:|---:|---:|
| Mandarin | 18.38 s | 21 / 3 | 561 ms | 26 ms | 0.161 | 1,515,896,832 B |
| Cantonese | 15.48 s | 20 / 1 | 549 ms | 26 ms | 0.117 | 1,512,554,496 B |
| Chinese-English mixed | 1.36 s | 3 / 1 | 568 ms | 33 ms | 0.978 | 1,512,243,200 B |
| 600 s composite | 600 s | 692 / 79 | 560 ms | 28 ms | 0.043 | 1,514,536,960 B |

Each of the three language slices produced changing partial output and a final
event after one completed input stream.  A speech-onset-trimmed measurement of
the same three slices observed the first changed partial at exactly 0.8 s in
each case (sample size three; not a P95 claim).

The same actor completed Mandarin twice in sequence, with `finish` at 561 ms
then 560 ms.  This proves `finish → accept → finish` creates and uses a fresh
sherpa stream rather than reusing one after `inputFinished()`.  A non-aligned
short final tail also reached a terminal final event.  The finalization padding
is 1.0 s: this is the minimum documented safety margin for the wrapper's
61-frame readiness threshold across residual alignment, and replaces the
insufficient 0.2 s attempt.

## State and quality limits

- Paraformer focused tests passed 11/11, including ordered partial changes,
  endpoint/session reset, final-tail handling, cancel/reset and empty input.
  SenseVoice regression tests passed 7/7.
- `cancel()` is covered before `inputFinished()` by unit state tests.  There is
  no live-microphone actor cancellation measurement in this work package.
- An untrimmed draft-only CER-like comparison was approximately 0.159
  (Mandarin), 0.368 (Cantonese), and 1.0 (mixed).  This is preview diagnostic
  evidence, not a quality acceptance metric; SenseVoice final must remain
  mandatory.
- Separate cold/warm model-load timings are not claimed.  The table reports
  end-to-end release-probe process timing only.

## Gate ruling

`G-A2-ASR` is passed for its narrow technical-probe scope: verified model
bundle/license, 1.13.6 online Swift build, changing output and terminal results
for Mandarin/Cantonese/mixed public samples, timing/RTF/RSS samples, safe
finish/reuse, and no dynamic hotword.  It does not pass product acceptance:
`AC-A2-003`, `AC-A2-004`, and `AC-A2-012` remain `in-progress` pending
WP-A2-03 product PCM, preview/fallback/copy, and acceptance-set evidence.
