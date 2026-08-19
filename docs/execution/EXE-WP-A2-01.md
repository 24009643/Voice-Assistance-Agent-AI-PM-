# EXE-WP-A2-01: Online Paraformer technical gate

- Plan: [`docs/plans/2026-08-19-wp-a2-01-paraformer-gate.md`](../plans/2026-08-19-wp-a2-01-paraformer-gate.md)
- Decision: [`ADR-0004`](../decisions/ADR-0004-alpha2-adaptive-dictation.md)
- Status: passed for the bounded technical probe; Alpha 2 product acceptance remains in progress
- Branch: `codex/wp-04-alpha2`
- Tested HEAD: `8f4b8ed` (probe implementation `c491cb5`)
- Commits: `b577459`, `18e3686`, `02b7a40`, `38b51c0`, `af0d191`, `979a638`, `c491cb5`
- Evidence: [`evidence/WP-A2-01-PARAFORMER.md`](../../evidence/WP-A2-01-PARAFORMER.md)

## Delivered scope

`probes/paraformer` owns an actual sherpa-onnx 1.13.6 online Paraformer
recognizer and an incremental WAV-to-JSONL probe.  It accepts normalized
`Float32` 16 kHz chunks (200 ms), emits ordered partial/final events, uses CPU
with one thread and greedy decoding, and exposes no dynamic-hotword setting.

The wrapper does not expose the upstream final-stream control.  `finish()`
therefore adds 1.0 s of silence before `inputFinished()` so the 61-frame
readiness threshold is reached despite residual chunk alignment.  It decodes
until not ready, emits its terminal result, then creates a fresh recognizer and
stream from the retained model bundle.  A cancelled active session resets before
`inputFinished()`.

## Commands and results

- `swift build -c release --package-path probes/paraformer` succeeded.
- The focused Paraformer package suite passed 11/11; the existing SenseVoice
  package suite passed 7/7.  These include ordered partial changes, endpoint
  reset, final-tail handling, cancel/reset and empty-input boundaries.
- The model bootstrap verification succeeded against the installed manifest and
  canonical Apache-2.0 `LICENSE`.
- Three public G0 WAV slices completed through `finish()` in the release probe;
  exact measurements and sources are in the linked evidence record.

## Traceability and acceptance boundary

| Requirement / criterion | Result in this work package | Remaining owner |
|---|---|---|
| `REQ-A2-003`, `AC-A2-003` | The probe proves bounded normalized chunk ingestion only.  It does not connect the app's PCM/WAV/level lifecycle. | WP-A2-03 |
| `REQ-A2-004`, `AC-A2-004` | Ordered Paraformer draft/final probe events work, including stream replacement after finish.  No product preview/fallback/copy ordering exists yet. | WP-A2-03 |
| `REQ-A2-005` | Cancel/reset is unit-covered for the probe; no live-microphone actor cancellation measurement was taken. | WP-A2-03 |
| `REQ-A2-012`, `AC-A2-012` | Release-probe timing, RTF and RSS are recorded.  Three onset-trimmed samples first changed at 0.8 s; this is not a product P95 acceptance set. | WP-A2-03, WP-A2-05 |

Accordingly, `AC-A2-003`, `AC-A2-004`, and `AC-A2-012` are `in-progress`, not
passed.  The technical `G-A2-ASR` gate is passed only in this probe scope:
model integrity, wrapper build, trilingual changing output, terminal handling,
performance samples, and no dynamic hotword are evidenced.  Separate
cold/warm model-load timings and live-microphone cancellation remain unclaimed.

## Deviations and risks

- A WAV EOF read attempted one extra `AVAudioFile.read` and prevented
  `finish()` on the first Mandarin smoke.  The reader is now bounded by
  `framePosition < length` and reads only remaining frames (`c491cb5`).
- Streaming text is a draft, not a quality substitute for SenseVoice: the
  untrimmed preview CER-like comparison is approximately Mandarin 0.159,
  Cantonese 0.368 and mixed 1.0.  SenseVoice final remains mandatory.
- First-change evidence has only three speech-onset-trimmed slices.  It must not
  be generalized to a product P95.

## Rollback

Revert the listed probe commits together; the app has not been changed by this
work package.  Generated model files, WAVs and JSONL remain outside Git.
