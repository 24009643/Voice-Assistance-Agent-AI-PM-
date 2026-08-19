# WP-A2-00 Alpha 2 design-freeze evidence

- Tested branch: `codex/wp-04-alpha2`
- Base commit: `584a7b1`
- Environment: macOS, 2026-08-19 +0800
- Gate: passed

## Proven

- ADR-0004 explicitly supersedes the conflicting ADR-0001 runtime/retention/LLM boundaries while retaining ADR-0002/0003 evidence.
- REQ-A2-001 through REQ-A2-012 each map to a work package and AC-A2 criterion.
- Four implementation plans name exact code boundaries, RED/GREEN checks, verification and commits.
- Training, LLM-generated training data, cloud ASR/audio upload, wake word and simulated paste are explicit exclusions and negative acceptance checks.
- Active Alpha 2 documents have no placeholder markers or legacy conflict phrases.
- `git diff --check` passed.

## Not yet proven

- Streaming Paraformer model/runtime performance.
- SessionBundle production behavior and visible copy UI.
- Live microphone latency and English quality.
- Terminology, export, Keychain/API and text-review runtime behavior.

These remain `not-entered` in the acceptance matrix and have dedicated WP plans; this document does not claim product completion.
