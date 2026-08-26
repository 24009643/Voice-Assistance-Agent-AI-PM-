# WP-A2-04 Terms, Export and Text Review Plan

> **Required workflow:** `superpowers:subagent-driven-development` and test-driven development.

**Goal:** Add deterministic local terminology, a controlled local corpus export and an optional text-only LLM review without any training path.

**Spec:** `docs/specs/tsb-v0.1-alpha2-design.md` REQ-A2-007, REQ-A2-008, REQ-A2-009, REQ-A2-010 and REQ-A2-011. WP-A2-03 must pass first.

## Task 1: Exact local terminology

- [ ] Add RED tests for term Save/Delete, normalized exact aliases, frozen revision, unmatched near-spellings and terminology edit provenance.
- [ ] Persist one atomic local `Terms/terms.json`; apply exact aliases after conservative cleanup and before record save.
- [ ] Add the smallest Settings UI required to list/add/edit/delete terms; do not claim model hotword bias.
- [ ] Run focused/full tests and commit `feat(text): add traceable terminology aliases`.

## Task 2: Private-corpus metadata and manual export

- [ ] Add RED tests proving an unreviewed selection is previewable but cannot export; then cover explicit review/selection, preview manifest, default audio exclusion, separate public-audio confirmation, PII warning, provenance/license fields and no network side effects.
- [ ] Reuse SessionBundle as the private corpus. Implement a local exporter that writes selected copies to a user-chosen directory; it never stages, commits, pushes or uploads.
- [ ] Add the minimal history/export UI required for selection, explicit review, confirmation and completion, plus confirmed deletion of one canonical bundle. Deletion is exact-root, idempotent, leaves legacy flat files untouched and has no clipboard side effect.
- [ ] Run focused/full tests, inspect an exported package and commit `feat(corpus): add controlled local export`.

## Task 3: API profile CRUD

- [ ] Add RED tests for Save/Cancel/Delete, HTTPS validation, Keychain-only secrets, stale callback/version protection, deletion idempotency and log redaction.
- [ ] Implement one profile store and native Settings form. Saved secrets are never read back into editable plaintext.
- [ ] Run focused/full tests and commit `feat(settings): add secure review profiles`.

## Task 4: Optional text-only review

- [ ] Add RED contract tests proving the request DTO has no URL/audio/path/session fields; add consent, timeout, invalid JSON, provider error, edit-trace and clipboard-unchanged tests.
- [ ] Implement one HTTPS JSON client for OpenAI-compatible chat endpoints, strict response decoding and a fixed conservative review instruction. No provider registry or background queue is added.
- [ ] Save the candidate as an independent review result. User actions are Review, Accept as saved candidate, Copy manually and Delete; none overwrite the original or auto-copy.
- [ ] Run focused/full tests, a mock-server network audit and commit `feat(review): add explicit text-only review`.

## Task 5: Trust gate evidence

- [ ] Add `EXE-WP-A2-04.md` and `evidence/WP-A2-04-TRUST.md` with the required mapping and actual outputs.
- [ ] Search source, plans and dependencies for training jobs, audio DTOs/uploads, wake listeners and simulated paste; record zero-path evidence or block the gate.
- [ ] Run full app tests, both probes, clean build, staged-path, binary, secret and `git diff --check` audits.
- [ ] Commit `docs(evidence): record Alpha 2 trust gate`.
