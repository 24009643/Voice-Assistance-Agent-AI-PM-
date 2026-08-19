# ADR-0004: Alpha 2 adaptive local dictation

- Status: Accepted
- Date: 2026-08-19
- Supersedes: the runtime, retention and LLM boundaries in ADR-0001
- Retains: ADR-0002 SenseVoice baseline and ADR-0003 public G0 corpus

## Context

The first Alpha proved the narrow local chain: hotkey, recording, whole-file SenseVoice, conservative cleanup, atomic text save and one clipboard write. Real use exposed three gaps: there is no live preview, sudden English terms are unstable in Chinese context, and successful audio is normally deleted even though early product validation needs aligned audio/text evidence.

The product remains a fast idea-capture tool. Training a speech model is not the product goal for this stage.

## Decision

Alpha 2 uses the following ordered chain:

```text
hotkey
  -> 16 kHz mono PCM + one session WAV
  -> Streaming Paraformer draft preview
  -> stop / closed utterance
  -> SenseVoice whole-WAV review
  -> deterministic cleanup + local terminology edits
  -> atomic session bundle
  -> one clipboard delivery + visible confirmation
  -> optional, explicit text-only LLM review
```

1. One non-cancelled capture owns one local `SessionBundle`:
   `~/Library/Application Support/TSB/Sessions/<UUID>/audio.wav` and `record.json`.
   Successful, no-speech and ASR-failed captures are retained by default. Explicit cancellation deletes only that bundle. Existing flat JSON and DebugAudio files are read in place and are not auto-migrated.
2. Streaming Paraformer produces a revisable preview. SenseVoice remains the authoritative local final candidate. If SenseVoice fails and the completed streaming candidate is non-empty, the app may deliver that candidate once with its source recorded.
3. The existing sherpa-onnx 1.13.6 package is reused. Paraformer is optional at startup: failure removes live preview but never blocks recording, SenseVoice finalization or clipboard delivery.
4. Dynamic model hotwords are not claimed for Streaming Paraformer because the selected online Paraformer path supports greedy decoding, while sherpa contextual biasing requires a supported transducer/modified-beam path. Alpha 2 instead applies exact, user-maintained terminology aliases after ASR and records each change.
5. Clipboard delivery occurs only after the bundle record is durable. A successful write immediately shows a green `已复制 · 按 ⌘V 粘贴` state for 1.2 seconds. A stale timer or older session cannot hide or overwrite a newer session.
6. Private session bundles form the early local evaluation corpus; no duplicate dataset store is created. A manual exporter may copy only explicitly selected, reviewed entries. Audio is included only after an explicit per-export public-audio confirmation; otherwise export is text and approved metadata only. Confirmed user deletion removes one exact canonical bundle. There is no background upload or automatic Git publication.
7. An optional LLM review is a separate, user-triggered, text-only action. Provider, model, HTTPS base URL and API key are user configured; the key stays in Keychain. The request cannot contain audio, PCM, file paths or a complete session object. The review result is an independent candidate with an edit trace and never automatically replaces the saved ASR text or clipboard.
8. The core local result must not wait for the LLM. LLM timeout, network failure and invalid output fall back to the already delivered local result.

## Explicit exclusions

- ASR fine-tuning, post-training, LoRA/adapters, pseudo-label training or continuous training.
- LLM-generated or LLM-labeled training data and any automated off-peak training/batch-labeling pipeline.
- Cloud ASR, audio upload, background dataset sync or automatic public release.
- Voice wake, always-on microphone, direct cursor insertion, simulated paste, Agent, memory or knowledge-base behavior.
- Automatic semantic rewriting, fact insertion or silent replacement of user meaning.

## Consequences

- Recording must move from whole-file-only `AVAudioRecorder` behavior to a single PCM source that writes the session WAV and feeds live ASR.
- Retained audio raises privacy risk. Runtime data stays out of Git and logs; users need bundle-level deletion before external beta release.
- The two local ASR outputs are provenance, not a complex fusion system: one draft, one final, one optional fallback.
- The first Paraformer change is a technical gate. It must prove model files, license, checksums, final-tail handling, latency, memory and cancellation before product integration.

## Verification

ADR-0004 is accepted only through the requirements and acceptance mapping in `docs/specs/tsb-v0.1-alpha2-design.md`. Every implementation record uses:

```text
WP -> ADR -> REQ -> production files -> focused tests -> AC -> evidence -> commit
```

No task or dependency may contain a training job, audio network request or automatic publication path.

## Rollback

Each Alpha 2 work package is independently revertible. If Streaming Paraformer fails its gate, retain the current SenseVoice-only local chain and the new session bundle; do not hide the failure behind a delayed offline preview.
