# WP-02 / AC-ASR-001 SenseVoice G0 gate evidence

- Date: 2026-08-19
- Device: Apple M5 Pro, arm64, 48 GiB memory (`51539607552` bytes)
- Branch: `codex/wp-03-alpha`
- Tested commit: `934da7c`
- Gate result: **PASS — technical G0 only**

## Scope

The pinned SenseVoiceSmall int8 model and sherpa-onnx runtime were tested against 20 Mandarin FLEURS clips, 20 Cantonese FLEURS clips, 20 ASCEND clips labeled `mixed`, and deterministic 180/240/300/600 second composites. Public corpus selection and licenses are frozen in `ADR-0003`.

The 60 short clips may be used for accuracy and performance observations. The four derived long files are licensed CC-BY-SA-4.0 and are valid only for stability, truncation, memory and RTF checks; they are not natural long-dictation accuracy evidence. Audio, references, raw transcripts, raw metrics and model weights remain in ignored `artifacts/`.

## Frozen model and runtime

- sherpa-onnx: `1.13.6`; onnxruntime-libs: `1.27.1`.
- Recognizer: `language=auto`, ITN enabled, CPU, one thread, greedy search.
- Input handling: whole WAV loaded locally, every frame preserved, sequential non-overlapping 30-second inference chunks, newline join.
- Model directory: ignored `artifacts/models/sensevoice-2024-07-17-int8/`.
- `model.int8.onnx`: SHA-256 `c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51`.
- `tokens.txt`: SHA-256 `f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc`.
- `LICENSE`: SHA-256 `221c6df10b0931a5629adad671ea48fb7747e034c414b6d2bfa275bc3dd4ea17`.
- Release probe: `39086768` bytes; SHA-256 `26ac5315015190f80f5fa3f8addb433ccbac9b5e03c80b6463ceb2c1391f376c`.
- Model regular files: `240506668` bytes.
- Conservative runtime binaries plus model: `419499380` bytes, below the 500 MB gate.

## Performance and stability

| Run | Samples | Audio seconds | Chunks | Max RTF | Active peak RSS delta | Output chars |
|---|---:|---:|---:|---:|---:|---:|
| Mandarin | 20 | 247.56 | 20 | 0.0271 | 964116480 B | 694 |
| Cantonese | 20 | 239.64 | 20 | 0.0272 | 924499968 B | 692 |
| Mixed | 20 | 48.26 | 20 | 0.0373 | 896024576 B | 342 |
| 180 s composite | 1 | 180 | 6 | 0.0275 | 958644224 B | 385 |
| 240 s composite | 1 | 240 | 8 | 0.0274 | 974602240 B | 586 |
| 300 s composite | 1 | 300 | 10 | 0.0276 | 978501632 B | 739 |
| 600 s composite | 1 | 600 | 20 | 0.0275 | 998064128 B | 1661 |

- All seven independent processes exited `0`, wrote a complete process record and left no residual `SenseVoiceProbe` process.
- Maximum observed RTF was `0.0373`, below `0.5`.
- Maximum active peak RSS delta was `998064128` bytes, below 2 GiB.
- Chunk counts equal `ceil(duration / 30 seconds)` for every long sample. Unit tests prove chunking preserves all frames in order.
- Long output length grows with duration and the 600-second run produced 1661 characters; the pre-fix one-shot run produced only 30 characters and used about 6.78 GiB active memory. The bounded path removes that truncation/memory failure.

## Accuracy observations, not a G0 quality pass

Normalization lowercased text and removed punctuation/whitespace; it did not convert traditional and simplified Chinese.

| Slice | Raw normalized CER | Language tags |
|---|---:|---|
| Mandarin | 0.046 | 20/20 `<|zh|>` |
| Cantonese | 0.382 | 20/20 `<|yue|>` |
| Mixed Chinese-English | 0.212 | 12 zh, 5 en, 2 yue, 1 ko |

The Cantonese result is a serious product risk. Traditional reference versus simplified output inflates the raw number, but does not explain it away. G0's written hard gate requires the slice to decode without crash/truncation and records accuracy for later comparison; it does not define a CER pass threshold. RC must use the user's consented Golden Set and the Whisper Tiny baseline before product-quality acceptance.

## Reproduction and raw hashes

```text
python3 -m unittest scripts/tests/test_prepare_g0_corpus.py
result: 5 tests passed.

python3 scripts/prepare_g0_corpus.py --samples 20 --output artifacts/corpora/g0
result: 64 manifest rows; 60 accuracy/performance, 4 stability-only.

swift test --package-path probes/sensevoice
result: 7 tests passed.

swift build --package-path probes/sensevoice -c release
result: passed.

SenseVoiceProbe run separately for mandarin, cantonese, mixed, 180 s, 240 s, 300 s and 600 s manifests
result: seven exit-0 processes; no residual process.
```

- Corpus manifest SHA-256: `df9cc9a0c3afaf5c903a07139b781b2f59eadf6355e57b7784c641831fa406f3`.
- Raw result SHA-256 values: Mandarin `318369ee4566f60b8087c93cabe0dc7db65180d3374856e062d4cb95c5cbd792`; Cantonese `79cf9a480105fafc2d01ecd08050f777fabed3577e8052d07351ae115634c249`; mixed `69ef6661bd3ecbd3ea4ecd92149d98ba53e1d1e23b5b1d5617449b9d09868db5`; 180 s `c5d7a27d6cab3327acde5ab3d41288843b61d0e283193f462a2d9cd5b2c25bba`; 240 s `c9f378254b271cab36c523fd4d319fa3115efff815fc69887ac64c0339565df8`; 300 s `ebad6f82603e5144c7e902453703b55720a85b042d1fa4612575891f6e4c4a18`; 600 s `a9f3b8cf4dc11f1dd9b19d1d765e80fbe795073d84ab4d517c9505a3bacf76e0`.
- Toolchain: macOS 26.5.2, Swift 6.3.3, Xcode 26.6.

## Decision

The SenseVoice baseline passes the written technical G0 gate. ADR-0002 is Accepted and WP-03 may begin. This does not approve Cantonese product quality, filler deletion, VAD, streaming preview or the RC Golden Set.
