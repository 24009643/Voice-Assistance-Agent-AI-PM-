# G0 Foundation and SenseVoice Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a reproducible TSB macOS shell and prove the exact SenseVoiceSmall runtime/model combination before product-chain implementation begins.

**Architecture:** WP-01 creates a minimal native app by selectively porting only OpenDictation's system-shell behavior into a new TSB tree. WP-02 is an isolated Swift command-line probe using the official sherpa-onnx package; it downloads models into ignored artifacts, measures real target-Mac behavior and produces a small sanitized evidence report.

**Tech Stack:** macOS 14+, Swift 6, Xcode 16+, XcodeGen, XCTest, Swift Package Manager, sherpa-onnx 1.13.6, SenseVoiceSmall int8 2024-07-17.

**Spec:** `docs/specs/tsb-v0.1-design.md`

## Global Constraints

- WP-01 owner: Terra. WP-02 owner: GPT-5.5. They use separate worktrees and do not edit each other's files.
- Sol is the only writer for shared root documentation, dependencies after integration and gate decisions.
- OpenDictation reference commit: `227c8b013ba4f4c7d8772b72f062354aae4443b1`.
- sherpa-onnx dependency: exact tag `1.13.6`.
- Probe model: `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17` with `useITN = true` and language `auto`.
- Model, VAD, audio and raw metrics live under ignored `artifacts/`.
- No LLM, cloud ASR, direct paste, Sparkle update or production history is implemented in G0.

---

### Task 1: Create the minimal TSB macOS project

**Files:**

- Create: `apps/macos/TSB/project.yml`
- Create: `apps/macos/TSB/Config/Shared.xcconfig`
- Create: `apps/macos/TSB/TSB/App/TSBApp.swift`
- Create: `apps/macos/TSB/TSB/App/AppIdentity.swift`
- Create: `apps/macos/TSB/TSB/Views/PlaceholderView.swift`
- Create: `apps/macos/TSB/TSBTests/AppIdentityTests.swift`
- Create: `apps/macos/TSB/UPSTREAM.md`

**Interfaces:**

- Consumes: macOS application lifecycle only.
- Produces: scheme `TSB`, module `TSB`, Release bundle ID `com.zhuohengchi.tsb`, Dev bundle ID `com.zhuohengchi.tsb.dev`.

- [ ] **Step 1: Write the failing identity test**

```swift
import XCTest
@testable import TSB

final class AppIdentityTests: XCTestCase {
    func testIdentityDoesNotUseUpstreamNamespace() {
        XCTAssertEqual(AppIdentity.productName, "TSB")
        XCTAssertEqual(AppIdentity.releaseBundleIdentifier, "com.zhuohengchi.tsb")
        XCTAssertEqual(AppIdentity.developmentBundleIdentifier, "com.zhuohengchi.tsb.dev")
        XCTAssertEqual(AppIdentity.keychainService, "com.zhuohengchi.tsb")
    }
}
```

- [ ] **Step 2: Generate and verify the intended red test**

Run:

```bash
cd apps/macos/TSB
xcodegen generate
xcodebuild -project TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

Expected: build reaches the test target and fails because `AppIdentity` is not defined. Toolchain or dependency failure is not an acceptable red test.

- [ ] **Step 3: Implement the identity and minimal app**

```swift
enum AppIdentity {
    static let productName = "TSB"
    static let releaseBundleIdentifier = "com.zhuohengchi.tsb"
    static let developmentBundleIdentifier = "com.zhuohengchi.tsb.dev"
    static let keychainService = "com.zhuohengchi.tsb"
}
```

`TSBApp` opens one plain `PlaceholderView` stating that the local dictation shell is not yet connected. Do not port cloud settings, update checks, history, insertion or ASR code in this task.

- [ ] **Step 4: Build and run the focused test**

Run the Step 2 command again.

Expected: `AppIdentityTests` passes and the Debug app target builds with signing disabled.

- [ ] **Step 5: Record provenance and commit**

`UPSTREAM.md` lists the OpenDictation URL, pinned commit, MIT license and the exact shell files considered for later selective porting.

```bash
git add apps/macos/TSB
git diff --cached --check
git commit -m "chore(app): establish minimal TSB macOS project"
```

### Task 2: Selectively port the macOS shell

**Files:**

- Create: `apps/macos/TSB/TSB/System/HotkeyService.swift`
- Create: `apps/macos/TSB/TSB/System/EscapeKeyMonitor.swift`
- Create: `apps/macos/TSB/TSB/System/MicrophonePermission.swift`
- Create: `apps/macos/TSB/TSB/System/Notch/NSScreen+Notch.swift`
- Create: `apps/macos/TSB/TSB/System/Notch/NotchWindow.swift`
- Create: `apps/macos/TSB/TSB/System/Notch/NotchOverlayPanel.swift`
- Create: `apps/macos/TSB/TSB/Views/Notch/NotchShape.swift`
- Create: `apps/macos/TSB/TSB/Views/Notch/NotchWaveformView.swift`
- Test: `apps/macos/TSB/TSBTests/System/HotkeyDebounceTests.swift`
- Test: `apps/macos/TSB/TSBTests/System/OverlayGenerationTests.swift`

**Interfaces:**

- Consumes: system key and display events.
- Produces: user intents and window events only; no recording or clipboard side effects.

- [ ] **Step 1: Write tests for key repeat and stale overlay callbacks**

The tests use a fake event source and `OverlayGeneration` value. Repeated key-down while the key is held emits one intent; a delayed hide callback with an older generation is ignored.

```swift
XCTAssertEqual(recorder.intents, [.toggleRecording])
XCTAssertFalse(currentGeneration.accepts(staleGeneration))
```

- [ ] **Step 2: Run the two test classes and verify red**

```bash
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:TSBTests/HotkeyDebounceTests -only-testing:TSBTests/OverlayGenerationTests test
```

Expected: missing shell types cause test compilation failure.

- [ ] **Step 3: Port the minimum reference behavior**

Copy only the relevant MIT-licensed logic from the pinned OpenDictation commit, rename it to the TSB namespace and remove app-specific ASR, cloud, insertion and update calls. Every imported file is listed in `UPSTREAM.md`.

- [ ] **Step 4: Run focused tests and Debug build**

Expected: both test classes and the TSB Debug build pass. No accessibility permission is requested.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/TSB
git diff --cached --check
git commit -m "feat(shell): add TSB hotkey and notch foundation"
```

### Task 3: Create the isolated SenseVoice probe package

**Files:**

- Create: `probes/sensevoice/Package.swift`
- Create: `probes/sensevoice/Sources/SenseVoiceProbe/ModelManifest.swift`
- Create: `probes/sensevoice/Sources/SenseVoiceProbe/ProbeResult.swift`
- Create: `probes/sensevoice/Sources/SenseVoiceProbe/main.swift`
- Create: `probes/sensevoice/Tests/SenseVoiceProbeTests/ModelManifestTests.swift`
- Create: `fixtures/manifest.example.jsonl`

**Interfaces:**

- Consumes: explicit model directory and a JSONL manifest containing local WAV paths and non-sensitive labels.
- Produces: one JSON result per audio file plus process-level cold load, peak RSS and total elapsed metrics.

- [ ] **Step 1: Define the exact package dependency**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SenseVoiceProbe",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/k2-fsa/sherpa-onnx", exact: "1.13.6")
    ],
    targets: [
        .executableTarget(
            name: "SenseVoiceProbe",
            dependencies: [.product(name: "sherpa-onnx", package: "sherpa-onnx")]
        ),
        .testTarget(name: "SenseVoiceProbeTests", dependencies: ["SenseVoiceProbe"])
    ]
)
```

- [ ] **Step 2: Write manifest-validation tests**

Tests reject a missing file, non-WAV extension, missing language label and duplicate sample ID. They accept Mandarin, Cantonese and mixed labels plus duration metadata.

- [ ] **Step 3: Run tests and verify red**

```bash
swift test --package-path probes/sensevoice --filter ModelManifestTests
```

Expected: missing manifest types cause compilation failure.

- [ ] **Step 4: Implement the minimum probe**

The probe configures the official offline recognizer with:

```text
model = <model-dir>/model.int8.onnx
tokens = <model-dir>/tokens.txt
language = auto
use_itn = 1
provider = cpu
decoding_method = greedy_search
```

It reads each 16kHz mono WAV, decodes once, records text/language/events/latency, and writes JSON to stdout. It never writes transcript text to normal application logs.

- [ ] **Step 5: Run tests and a no-model argument check**

```bash
swift test --package-path probes/sensevoice
swift run --package-path probes/sensevoice SenseVoiceProbe --help
```

Expected: tests pass; help exits 0 without downloading or loading a model.

- [ ] **Step 6: Commit**

```bash
git add probes/sensevoice fixtures/manifest.example.jsonl
git diff --cached --check
git commit -m "feat(probe): add reproducible SenseVoice benchmark"
```

### Task 4: Add deterministic model bootstrap

**Files:**

- Create: `scripts/bootstrap-sensevoice-model.sh`
- Create: `docs/decisions/ADR-0002-sensevoice-baseline.md`
- Modify: `.gitignore`

**Interfaces:**

- Consumes: official HTTPS release URL.
- Produces: `artifacts/models/sensevoice-2024-07-17-int8/`, computed SHA-256 values and license copy.

- [ ] **Step 1: Write the script's local self-check**

The script accepts `--verify-only`. It fails if `model.int8.onnx`, `tokens.txt` or `LICENSE` is missing, or if a recorded checksum differs.

- [ ] **Step 2: Use the official model URL**

```text
https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2
```

The script downloads to a temporary file, extracts only into `artifacts/models`, computes SHA-256 with `shasum -a 256`, and writes `manifest.sha256`. It does not commit the archive or extracted model.

- [ ] **Step 3: Verify repository exclusion**

```bash
git check-ignore artifacts/models/sensevoice-2024-07-17-int8/model.int8.onnx
git status --short
```

Expected: the model is ignored and no model file appears in Git status.

- [ ] **Step 4: Commit only script and ADR shell**

ADR-0002 records the candidate, official source, license location, runtime version and the exact evidence required before its status can become Accepted. Its initial status is Proposed, not Passed.

```bash
git add scripts/bootstrap-sensevoice-model.sh docs/decisions/ADR-0002-sensevoice-baseline.md .gitignore
git diff --cached --check
git commit -m "chore(asr): pin SenseVoice probe inputs"
```

### Task 5: Run G0 and record the gate

**Files:**

- Create: `evidence/WP-02-AC-ASR-001-sensevoice-probe.md`
- Create: `docs/execution/EXE-WP-02.md`
- Modify: `docs/decisions/ADR-0002-sensevoice-baseline.md`

**Interfaces:**

- Consumes: target-Mac audio manifest and ignored raw output.
- Produces: sanitized gate decision with commit, environment, model/runtime hashes, RTF, memory, disk and failure counts.

- [ ] **Step 1: Verify the model and run short official samples**

```bash
scripts/bootstrap-sensevoice-model.sh --verify-only
swift run --package-path probes/sensevoice SenseVoiceProbe \
  --model-dir artifacts/models/sensevoice-2024-07-17-int8 \
  --manifest artifacts/fixtures/g0-short.jsonl \
  > artifacts/results/g0-short.json
```

- [ ] **Step 2: Run the user-language and long-duration set**

Run the same command against Mandarin, Cantonese, mixed Chinese-English, three 3–5 minute samples and one 10 minute sample. Raw audio and JSON remain ignored.

- [ ] **Step 3: Evaluate the hard gate**

Pass only when RTF ≤ 0.5, peak ASR memory increase ≤ 2GB, model/runtime ≤ 500MB, all samples finish without truncation, and resources return after each run. Accuracy metrics are recorded by language for comparison; product quality is decided again at RC with the full Golden Set.

- [ ] **Step 4: Update evidence and ADR**

If all hard checks pass, mark ADR-0002 Accepted. Otherwise keep it Proposed or mark it Rejected with the failing evidence; do not begin WP-03.

- [ ] **Step 5: Commit the sanitized result**

```bash
git add evidence/WP-02-AC-ASR-001-sensevoice-probe.md docs/execution/EXE-WP-02.md docs/decisions/ADR-0002-sensevoice-baseline.md
git diff --cached --check
git commit -m "docs(asr): record SenseVoice G0 decision"
```

### Task 6: Integration review

**Files:**

- Modify: `docs/execution/EXE-WP-01.md`
- Modify: `docs/execution/EXE-WP-02.md`

- [ ] **Step 1:** Sol verifies each branch diff, staged file boundary and fresh command output.
- [ ] **Step 2:** Merge WP-01 and WP-02 sequentially into the integration branch; resolve dependencies only through Sol-owned files.
- [ ] **Step 3:** Run the TSB Debug build, app tests and probe tests from the merged tree.
- [ ] **Step 4:** Confirm no model, audio, nested `.git`, DMG, secret or generated project artifact is tracked.
- [ ] **Step 5:** If G0 passed, create annotated tag `tsb-0.1-g0-pass`; otherwise publish the evidence without a pass tag and stop feature execution.

## Official references

- sherpa-onnx Swift package: https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.6/Package.swift
- SenseVoice integration: https://k2-fsa.github.io/sherpa/onnx/sense-voice/index.html
- SenseVoice int8 model and VAD usage: https://k2-fsa.github.io/sherpa/onnx/sense-voice/pretrained.html
- SenseVoice C API configuration reference: https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.6/c-api-examples/sense-voice-c-api.c
