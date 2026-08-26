# WP-A2-02 Session Bundle and Copy Truth Plan

> **Required workflow:** `superpowers:subagent-driven-development` and test-driven development.

**Goal:** Retain aligned audio/text for every non-cancelled capture and make clipboard success visibly truthful.

**Spec:** `docs/specs/tsb-v0.1-alpha2-design.md` REQ-A2-001, REQ-A2-002, REQ-A2-005, REQ-A2-006.

## Task 1: Canonical bundle storage

- [ ] Add RED tests in `TSBTests/Core/Storage/TranscriptStoreTests.swift` for canonical `Sessions/<UUID>/record.json`, legacy flat read, canonical precedence, atomic status rewrite, exact-root idempotent deletion and path escape rejection.
- [ ] Extend the existing record with outcome/error/final-source plus language-slice, local-evaluation-consent, review-state and intended-use fields and backward-compatible decoding; do not add a second record hierarchy.
- [ ] Change `TranscriptStore` to canonical bundle reads/writes and explicit `removeSession(id:)`; leave legacy files untouched.
- [ ] Run focused tests, full app tests and `git diff --check`.
- [ ] Commit `feat(storage): add retained session bundles`.

## Task 2: Record directly into the bundle

- [ ] Add RED audio tests for `Sessions/<UUID>/audio.wav`, successful retention, failed/no-speech retention, exact-bundle cancellation, repeated callbacks and failed start cleanup.
- [ ] Make the recorder and store share the Sessions root. Remove the production DebugAudio finalizer path and its obsolete tests.
- [ ] Keep normal completion in place; cancellation removes only its session directory.
- [ ] Run focused/full tests and verify no legacy user file is moved or deleted.
- [ ] Commit `refactor(audio): record into session bundle`.

## Task 3: Preserve outcome and copy truth

- [ ] Add RED coordinator tests for success, ASR failure, no speech, save failure, copy failure, copy-success/status-write-failure, cancellation during ASR and late callbacks.
- [ ] Persist an outcome record before publishing terminal state. Copy only after the local record is durable and never retry automatically after a true pasteboard write.
- [ ] Publish the exact delivered or warning snapshot on the main actor with session ownership checks.
- [ ] Run coordinator/full tests and the SenseVoice probe.
- [ ] Commit `fix(session): preserve bundle and clipboard truth`.

## Task 4: Visible copy confirmation

- [ ] Add RED overlay/view tests for a green accessible delivered state, exact Chinese message, no false-success styling and a stale 1.2-second dismissal that cannot overwrite a newer snapshot.
- [ ] Reuse the existing snapshot and native SF Symbol/color; do not add a second view model or copy timer.
- [ ] Verify the fallback window and notch overlay render the same truth.
- [ ] Run focused/full tests, clean build and `git diff --check`.
- [ ] Commit `feat(ui): confirm automatic copy`.

## Task 5: Record G-A2-DATA evidence

- [ ] Add `docs/execution/EXE-WP-A2-02.md` with `WP -> ADR -> REQ -> files -> tests -> AC -> evidence -> commit` rows.
- [ ] Add `evidence/WP-A2-02-SESSION-BUNDLE.md` with automated outputs and the shortest manual audio/copy smoke.
- [ ] Verify ignored runtime data, no staged audio/text, exact staged paths and clean tree.
- [ ] Commit `docs(evidence): record session bundle gate`.
