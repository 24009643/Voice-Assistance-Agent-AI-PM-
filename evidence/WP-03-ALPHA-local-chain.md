# WP-03 Alpha local-chain evidence

- Date/time: 2026-08-19 13:02:24–13:02:48 +0800
- Device: target Apple silicon Mac (M5 Pro, 48 GiB memory)
- Branch: `codex/wp-03-evidence`
- Tested main merge: `61c1cb3919d493b9d452354120867a4409fee1ae`
- Gate result: **PENDING / NOT PASSED**

## What was verified

| Check | Actual result | Exit code |
|---|---|---:|
| Xcode project generation | `xcodegen generate --spec apps/macos/TSB/project.yml` completed | 0 |
| Clean macOS app test run | 44 tests passed, 0 failures | 0 |
| SenseVoice probe tests | 7 tests passed, 0 failures | 0 |
| Frozen model manifest | `model.int8.onnx`, `tokens.txt`, `LICENSE` SHA-256 checks all `OK` | 0 |
| Repository diff check | `git diff --check` clean; worktree clean | 0 |
| Application launch/liveness | Started with frozen model, ran 17 seconds, RSS `1173136 KiB`, no crash, no residual process after termination | observed |

The launch/liveness observation used the frozen model directory:

```text
/Users/zhuohengchi/Desktop/The Second Brain/.worktrees/wp-02-g0-run/artifacts/models/sensevoice-2024-07-17-int8
```

No microphone capture was initiated during this evidence collection.

## Known warnings retained with the evidence

- Xcode reported multiple matching macOS destinations and selected the first.
- Xcode warned that the onnxruntime XCFramework `Versions/Current` symlink could not be resolved.
- The test host emitted `linkd.autoShortcut` connection warnings.
- The ASR WAV validation test emitted a non-interleaved-audio-setting warning.

The commands in the table exited 0 despite these warnings. They are not interpreted as a human dictation pass.

## Why the gate is still pending

The following single-user path has not yet been witnessed on this machine:

```text
microphone → real ASR → saved JSON → exactly one clipboard write → Command-V paste
```

Without that observation, this evidence does not establish real microphone permission behavior, model handoff from captured WAV, session persistence, or single clipboard delivery. Do not create a release/Alpha tag from this evidence.

## Manual acceptance: shortest reproducible path

1. Export `TSB_SENSEVOICE_MODEL_DIR` with the frozen-model path above and launch the Debug app.
2. Grant microphone access. Press Option-Space, dictate 5–15 seconds, then press Option-Space again.
3. Open TextEdit and press Command-V once. Locate the matching JSON file under `~/Library/Application Support/TSB/Sessions/`.

Acceptance passes only when the JSON contains preserved `originalText`, its delivery status records the clipboard outcome, exactly one delivered string is pasted, and no second session or duplicate text appears. A failure leaves this evidence at **PENDING / NOT PASSED**; preserve any generated JSON and temporary WAV for diagnosis.

## Intentionally absent from this gate

- VAD and stable segmented preview
- Push-to-talk
- Overlapping sessions
- Custom result card
- Retention controls
- API profile / LLM integration
- Golden Set quality validation
