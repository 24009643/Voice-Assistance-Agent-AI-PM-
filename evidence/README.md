# Evidence Index

- [`WP-HYGIENE-LOCAL-GATE.md`](WP-HYGIENE-LOCAL-GATE.md): bounded local
  repository, test, privacy and unsigned Debug-build evidence; remote and
  product/release gates remain unproven.
- [`WP-A2-00-DESIGN-FREEZE.md`](WP-A2-00-DESIGN-FREEZE.md): Alpha 2 decision,
  requirements, plans and acceptance mapping freeze. It proves documentation
  consistency only, not runtime completion.
- [`WP-A2-01-PARAFORMER.md`](WP-A2-01-PARAFORMER.md): bounded online
  Paraformer model provenance and release-probe evidence; it does not pass the
  product acceptance criteria.
- [`WP-A2-02-SESSION-BUNDLE.md`](WP-A2-02-SESSION-BUNDLE.md): bounded canonical
  SessionBundle, retained outcome, clipboard-truth and visible confirmation
  evidence; manual microphone-to-clipboard acceptance remains open.

This directory contains small, reviewable evidence and indexes for acceptance decisions. Generated Xcode output, model files, audio and raw logs remain ignored.

Evidence file names start with the work package and criterion, for example:

```text
WP-02-AC-ASR-001-sensevoice-probe.md
WP-05-AC-IDEMP-003-overlapping-sessions.md
```

Each file records environment, commit, command, expected result, actual result and linked artifact hash. A claim is not marked passed without fresh evidence from the target Mac.
