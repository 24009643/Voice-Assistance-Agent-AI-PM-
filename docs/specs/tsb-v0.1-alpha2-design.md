# TSB 0.1 Alpha 2 Design

- Status: Approved for incremental implementation
- Date: 2026-08-19
- Decision authority: ADR-0004
- Replaces for active work: `tsb-v0.1-design.md`

## 1. Product outcome

Alpha 2 turns the proven local dictation chain into a fast, observable capture loop:

> speak -> see a live draft -> stop -> receive a reviewed local result within 3 seconds -> paste anywhere -> retain an aligned private audio/text record

The authoritative outcome is still captured user intent, not model creativity. A local result is usable without network or an API key.

## 2. Scope and requirement IDs

| ID | Requirement |
|---|---|
| REQ-A2-001 | A non-cancelled capture persists one local session bundle containing `audio.wav` and `record.json`; explicit cancellation or confirmed user deletion removes only the selected bundle. |
| REQ-A2-002 | Success, ASR failure and no-speech outcomes retain aligned audio and metadata by default; existing flat records are read without automatic migration. |
| REQ-A2-003 | A single 16 kHz mono PCM source drives WAV persistence, audio level and live ASR without keeping a second full recording in memory. |
| REQ-A2-004 | Streaming Paraformer produces revisable preview text; SenseVoice produces the authoritative final candidate; source and timing are persisted. |
| REQ-A2-005 | Stop, Escape, device failure and the 10-minute limit release audio and ASR resources exactly once; stale callbacks cannot cross sessions. |
| REQ-A2-006 | A successful clipboard write occurs at most once after durable local save and produces visible, accessible copy confirmation; failure never displays success. |
| REQ-A2-007 | User-maintained exact terminology aliases are local and deterministic; every applied change is a persisted edit operation and fuzzy guessing is forbidden. |
| REQ-A2-008 | Private bundles form the local evaluation corpus and remain ignored by Git, logs and network clients. |
| REQ-A2-009 | Manual export requires an explicitly reviewed item, selection, preview and confirmation; public audio requires an additional explicit confirmation and provenance/license metadata. |
| REQ-A2-010 | API profiles support Save/Cancel/Delete with Keychain secrets. Optional LLM review is explicit, text-only, non-blocking and independently persisted. |
| REQ-A2-011 | No audio leaves the Mac; no runtime path performs post-training, training-data generation, cloud ASR, wake-word listening or automatic paste. |
| REQ-A2-012 | On the M5 Pro/48 GB target, live draft first-update P95 is at most 800 ms, stop-to-local-final P95 at most 1.5 s, and stop-to-copy P95 at most 2 s with a hard 3 s ceiling. |

## 3. Runtime flow

```text
UserIntent
  -> SessionCoordinator
  -> PCM capture ─┬─> session/audio.wav
                  ├─> level meter
                  └─> Streaming Paraformer -> preview only
  -> stop/limit
  -> SenseVoice(session/audio.wav) -> local final candidate
  -> ConservativeCleaner -> terminology aliases -> EditOperation[]
  -> atomic session/record.json
  -> ClipboardService.copy exactly once
  -> delivered UI (green check, 1.2 s)
  -> optional explicit text-only review
```

Paraformer initialization and decode failure degrade to the existing SenseVoice path. SenseVoice failure may use a non-empty completed Paraformer result once, marked `streamingFallback`. Neither preview nor LLM review can independently trigger automatic clipboard delivery.

## 4. Session bundle contract

```text
~/Library/Application Support/TSB/Sessions/<UUID>/
  audio.wav
  record.json
```

`record.json` contains:

- session ID, ordinal, timestamps, duration and outcome;
- streaming completed text and SenseVoice text as separate optional fields;
- selected final source: `senseVoice` or `streamingFallback`;
- cleaned text and ordered edit operations;
- terminology revision used for the session;
- language slice, local-evaluation consent, review state and intended use;
- delivery status and non-sensitive timing metrics;
- optional LLM review metadata/result, never an API key.

Canonical reads prefer the bundle, then the legacy `Sessions/<UUID>.json`. Legacy DebugAudio may be shown as a diagnostic attachment but is not moved automatically. Bundle writes are atomic at `record.json`; bundle deletion is idempotent and path-confined to the exact Sessions root.

## 5. Real-time and final ASR

### 5.1 Streaming Paraformer gate

The gate fixes model name, files, license and checksums before integration. The initial candidate is `sherpa-onnx-streaming-paraformer-trilingual-zh-cantonese-en` with `encoder.int8.onnx`, `decoder.int8.onnx` and `tokens.txt` under a local ignored model directory.

The adapter owns the non-Sendable recognizer in one actor. It receives normalized Float32 chunks near 200 ms, publishes only changed text, pads the final tail, calls `inputFinished`, and resets on cancel. If tail loss remains, a thin wrapper exposing the upstream final-stream option is allowed only after a failing probe proves it necessary.

### 5.2 SenseVoice review

SenseVoice continues to read the same complete WAV with the pinned 1.13.6 runtime. The first product slice reviews the whole WAV once; it does not maintain per-segment PCM copies or run parallel SenseVoice workers. This is the shortest path to better English recovery without risking duplicated text or clipboard writes.

### 5.3 Performance accounting

Evidence records cold/warm model load, first preview, preview refresh, streaming RTF, SenseVoice final, persistence, clipboard, peak memory, cancellation and the final tail. Mandarin, Cantonese and random Chinese-English code switching are reported separately; averages cannot hide one slice.

## 6. Terminology and correction

The local terminology file contains canonical term, normalized exact aliases, optional note and revision. A frozen revision is loaded at session start. Exact aliases may correct final local text and must produce `EditOperation(reason: terminology)`. Similar strings that do not exactly match remain unchanged and may be shown as a suggestion later.

Streaming Paraformer dynamic hotwords are not part of Alpha 2 because the selected greedy Paraformer implementation does not support the contextual-biasing path. A future transducer evaluation requires a separate ADR and benchmark; it is not hidden behind the term store.

## 7. Clipboard and UI behavior

- Recording: live level plus Paraformer draft. Draft changes in place and is labelled `实时草稿`.
- Processing: the last draft remains visible with `本地复核中`.
- Delivered: green check and exact text `已复制 · 按 ⌘V 粘贴`, visible for 1.2 seconds.
- Failed clipboard: no green check and a manual copy action.
- Copy succeeded but status persistence failed: `已复制，但未能记录复制状态`; never auto-copy again.
- A new recording immediately owns the main card. Older processing/review work moves to a secondary card and cannot reset or overwrite the newer session.

UI derives these states from the coordinator snapshot. It does not call ASR, storage, clipboard or network clients.

## 8. Private corpus and manual export

Retained session bundles are the private evaluation corpus; no second copy is created. Each record stores language slice, consent state, review state and intended use. Default use is local evaluation/regression only.

Manual export is a local file operation with five gates: the entry is explicitly marked reviewed, explicit item selection, content preview, PII warning and final confirmation. An unreviewed item may appear in preview but cannot be exported. Text and approved metadata are the default. Audio is included only when the user separately enables public audio for that export. The exporter writes a manifest, provenance, model/output versions and a data-license placeholder requiring user selection before publication. It never pushes Git or calls a network API.

History also supports confirmed deletion of one selected canonical bundle. Deletion is path-confined and idempotent, has no clipboard side effect, and does not silently remove legacy flat files.

## 9. Optional text-only LLM review

The core product never requires the reviewer. The user configures provider, model, HTTPS base URL and API key, then explicitly chooses a saved local text version and starts review.

The request DTO can contain only the selected text, selected terminology entries, language hint and review instruction. It cannot contain `URL`, audio, PCM, session directory or the complete record. The first review instruction permits punctuation, obvious ASR homophone/English-term correction and minimal filler removal; it forbids summarization, idea restructuring, fact insertion and meaning changes.

The response is strict JSON with candidate text and edit operations. Invalid JSON, timeout or provider error preserves the local result. Review never blocks the 3-second local-copy budget and never automatically copies or replaces text. Save/Cancel/Delete are real API-profile operations; secrets remain only in Keychain and logs contain no request text.

## 10. Failure rules

- Recording start failure leaves no empty bundle.
- Explicit cancellation removes only the active bundle and produces no clipboard write.
- ASR/no-speech failure retains audio plus an outcome record.
- Streaming failure disables preview for that session and continues to SenseVoice.
- SenseVoice failure uses a completed non-empty streaming fallback once; otherwise no copy.
- Record save failure retains audio and forbids copy.
- Clipboard failure retains the record and previous clipboard content.
- LLM/API failure cannot change the saved local result or clipboard.
- All awaited callbacks re-check active session ownership before changing state.

## 11. Privacy and repository rules

Runtime audio, transcripts, session bundles, credentials and model weights remain outside Git. Curated export output is also outside Git until the user explicitly reviews and chooses publication. Logs record only IDs, stage, durations, model version, character counts and error categories.

The codebase contains no training job, training queue, optimizer, dataset uploader, audio network DTO, wake-word listener or simulated paste path. These are negative acceptance checks, not future scaffolding.

## 12. Incremental delivery and traceability

| Work package | Design output | Code/output boundary | Requirements | Acceptance |
|---|---|---|---|---|
| WP-A2-00 | ADR, canonical spec, plans and mapping | docs only | all | document consistency audit |
| WP-A2-01 | Streaming feasibility | `probes/paraformer`, model manifest, evidence | REQ-A2-003, REQ-A2-004, REQ-A2-005, REQ-A2-012 | AC-A2-003, AC-A2-004, AC-A2-012 |
| WP-A2-02 | Session bundle and copy truth | Domain, Audio, Storage, Coordinator, copy UI | REQ-A2-001, REQ-A2-002, REQ-A2-005, REQ-A2-006 | AC-A2-001, AC-A2-002, AC-A2-005, AC-A2-006 |
| WP-A2-03 | Product live preview | Audio PCM fan-out, Paraformer adapter, coordinator/UI | REQ-A2-003, REQ-A2-004, REQ-A2-005, REQ-A2-006, REQ-A2-012 | AC-A2-003, AC-A2-004, AC-A2-005, AC-A2-006, AC-A2-012 |
| WP-A2-04 | Terms, export and text review | local term/export stores, Settings/Review | REQ-A2-007, REQ-A2-008, REQ-A2-009, REQ-A2-010, REQ-A2-011 | AC-A2-007, AC-A2-008, AC-A2-009, AC-A2-010, AC-A2-011 |
| WP-A2-05 | Release evidence | focused/full tests, real-device benchmark and privacy audit | REQ-A2-001 through REQ-A2-012 | AC-A2-001 through AC-A2-012 |

Every execution record has exactly one mapping table:

```text
WP -> ADR-0004 -> REQ-A2 -> production files -> focused tests -> AC-A2 -> evidence -> commit
```

## 13. Release boundary

Alpha 2 is complete only when the target Mac proves the local live/final chain, aligned retained bundles, one visible clipboard delivery, deterministic terminology, private corpus/export boundary and optional text reviewer contracts. The following remain later-stage work: training of any kind, voice wake, cursor insertion, automatic paste, cloud ASR, automatic dataset publication, Agent/knowledge-base behavior and semantic idea restructuring.
