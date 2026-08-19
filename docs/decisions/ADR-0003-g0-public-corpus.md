# ADR-0003: Use public speech corpora for the repeatable G0 gate

- Status: Accepted
- Date: 2026-08-19
- Owners: Sol, GPT-5.5 reviewer

## Context

ADR-0002 cannot be accepted from the model vendor's five demonstration WAV files alone. G0 needs repeatable Mandarin, Cantonese and real Chinese-English code-switching inputs without committing audio, transcripts or personal recordings to Git.

## Decision

Use a small, locally generated corpus:

- Mandarin: 20 FLEURS `cmn_hans_cn` development clips, CC-BY-4.0.
- Cantonese: 20 FLEURS `yue_hant_hk` development clips, CC-BY-4.0.
- Chinese-English mixed: 20 ASCEND test clips whose published `language` is `mixed`, CC-BY-SA-4.0.
- Long stability inputs: deterministic 180, 240, 300 and 600 second concatenations of those clips with 500 ms silence between clips. These derived files use CC-BY-SA-4.0 and are valid only for stability, truncation, memory and RTF checks—not natural long-dictation accuracy.

Run:

```bash
python3 -m unittest scripts/tests/test_prepare_g0_corpus.py
python3 scripts/prepare_g0_corpus.py --samples 20 --output artifacts/corpora/g0
```

Use `--force` only when intentionally replacing files inside that exact output directory. The ignored `manifest.jsonl` records dataset, split, source URL, license, reference text, evaluation scope, duration and SHA-256 for each generated WAV.

## Consequences

- The repository contains only the preparation code and tests; downloaded audio and generated manifests remain under ignored `artifacts/`.
- Public samples make G0 reproducible, but they do not replace the user's later private Golden Set.
- FLEURS is read speech. ASCEND is spontaneous code-switching but contains short segments. Product-quality filler handling, accent coverage and natural 3–10 minute dictation still require consented user recordings later.
- The preparation script fails loudly if the Hugging Face viewer changes ASCEND's audio field shape or returns an unsafe remote ID.

## Verification

- 64 manifest rows: 20 Mandarin, 20 Cantonese, 20 mixed and 4 derived long files.
- 60 rows have `evaluation_scope=accuracy_and_performance`; 4 have `evaluation_scope=stability_only`.
- Every WAV is 16 kHz, mono, PCM16 and has a SHA-256 digest.
- Unit tests cover archive traversal, real mixed-row selection, remote-ID and API-shape rejection, composite scope/license, and overwrite confirmation.

## Rollback

Delete the ignored `artifacts/corpora/g0/` directory and revert the corpus preparation commit. ADR-0002 remains independently reversible.
