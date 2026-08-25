# TSB Daily Runtime Activation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the stale temporary TSB process with a stable local build that discovers both ASR models without launch-only environment variables, then verify the real recording, copy, and optional cloud-organization stages.

**Architecture:** Reuse the existing canonical Application Support model pattern already used by Paraformer. Do not change the recording UI until the latest build is actually running and the live PCM-to-Paraformer chain has been tested. Keep local transcription/copy before optional remote organization; cloud settings and Keychain binding remain explicit configuration, not build defaults.

**Tech Stack:** Swift 6, SwiftUI, AppKit, AVFoundation, sherpa-onnx, XCTest, macOS 14+

**Spec:** `docs/superpowers/specs/2026-08-25-tsb-v0.2-recording-runtime-design.md`

## Global Constraints

- Work in `codex/wp-04-alpha2`; do not merge, push, or release.
- Never terminate an active recording or replace the running process without confirming it is safe.
- Microphone is active only during a user-started recording; resident app does not mean resident microphone capture.
- Do not send audio, paths, keys, or unselected history to a Provider.
- Do not add a dependency, second model registry, fake progress UI, silence stop, or background microphone.
- Every production change follows RED, minimal GREEN, focused suite, full regression, review.

---

### Task 1: Resolve SenseVoice from the canonical Application Support bundle

**Files:**
- Modify: `apps/macos/TSB/TSB/Core/Transcription/SenseVoiceTranscriber.swift`
- Modify: `apps/macos/TSB/TSB/App/AppController.swift`
- Modify: `apps/macos/TSB/TSBTests/Core/Transcription/SenseVoiceTranscriberTests.swift`

**Interfaces:**
- Consumes: `SenseVoiceModelLocation.init(directory:)`, `TSB_SENSEVOICE_MODEL_DIR`, the Paraformer canonical-location pattern.
- Produces: `SenseVoiceModelLocation.resolvedLocation(environment:applicationSupportDirectory:)` with override-first behavior and canonical fallback.

- [ ] **Step 1: Add canonical-resolution RED tests**

Add literal-path tests proving an explicit environment override wins and an empty environment resolves `<Application Support>/TSB/Models/<SenseVoiceModelLocation.modelName>`.

```swift
func testResolvedLocationPrefersExplicitEnvironmentOverride() throws
func testResolvedLocationUsesCanonicalApplicationSupportBundle() throws
func testDevelopmentLocationWithoutOverrideKeepsStrictMissingDirectoryError() throws
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:TSBTests/SenseVoiceTranscriberTests test
```

Expected: compile failure because `modelName` and `resolvedLocation` do not exist.

- [ ] **Step 3: Implement the minimum resolver and switch the app consumer**

Mirror the existing Paraformer resolver: environment override first, otherwise the canonical user Application Support model directory. Keep `developmentLocation(environment:)` strict for probe/tests. Change the default `AppController` startup to use `resolvedLocation()`.

- [ ] **Step 4: Run GREEN and model-guard regressions**

```bash
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:TSBTests/SenseVoiceTranscriberTests \
  -only-testing:TSBTests/SessionCoordinatorTests/testMenuStartWithMissingSenseVoiceDoesNotRequestPermissionOrStartRecording test
```

- [ ] **Step 5: Commit**

```bash
git add apps/macos/TSB/TSB/Core/Transcription/SenseVoiceTranscriber.swift \
  apps/macos/TSB/TSB/App/AppController.swift \
  apps/macos/TSB/TSBTests/Core/Transcription/SenseVoiceTranscriberTests.swift
git commit -m "fix(v0.2): discover stable SenseVoice bundle"
```

---

### Task 2: Prepare and verify one stable local app bundle

**Files:**
- No tracked source file unless Task 1 verification exposes a defect.

**Interfaces:**
- Consumes: canonical SenseVoice and Paraformer model directories, current app build.
- Produces: one fixed-path local `TSB.app` whose executable differs from the stale temporary process and whose two model manifests validate.

- [ ] **Step 1: Copy the already validated SenseVoice bundle atomically into its canonical Application Support directory**

Use the existing verified local model as source. Create a sibling temporary directory, verify all required files and `manifest.sha256`, then rename only when the canonical target does not already exist. Do not download or overwrite a valid target.

- [ ] **Step 2: Run the focused suite, complete macOS suite, both probes, and a fresh Debug build**

```bash
xcodegen generate --spec apps/macos/TSB/project.yml
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/tsb-daily-runtime-build CODE_SIGNING_ALLOWED=NO build
swift test --package-path probes/sensevoice
swift test --package-path probes/paraformer
```

- [ ] **Step 3: Install without starting or terminating a process**

Copy the verified build to one fixed user Applications path only after resolving the exact target and confirming no existing target would be overwritten unexpectedly. Record executable hash and bundle identifier. Do not launch while the stale TSB process or an active recording remains.

---

### Task 3: Run the user-present recording and organization acceptance

**Files:**
- Modify evidence documents only after observations exist.

**Interfaces:**
- Consumes: stable app, canonical models, explicit organization settings, endpoint-bound Keychain secret.
- Produces: real observations for live preview, Stop, final copy, local persistence, and optional DeepSeek organization.

- [ ] **Step 1: Replace the stale process only after the user confirms recording is stopped**

Quit the old temporary-path TSB, launch the fixed-path app, and verify only one TSB process owns Option-Space.

- [ ] **Step 2: Verify live and local stages**

Record one non-sensitive sentence. Require visible elapsed time and changing live draft while speaking. Press Stop; require `本地复核中`, then `已复制 · 按 ⌘V 粘贴`, plus a durable session bundle. Esc before Stop deletes; Esc after Stop does not delete.

- [ ] **Step 3: Restore cloud organization explicitly**

Confirm the non-secret endpoint is the approved DeepSeek Chat Completions endpoint, consent version is current, and a matching Keychain-bound secret exists without displaying it. Do not reuse the current loopback acceptance endpoint. Send only the newly recorded non-sensitive text and no history summary for the first check.

- [ ] **Step 4: Verify organization stages**

After local copy, require `本地稿已复制 · 正在整理`, then either `整理完成` with the three chambers and privacy receipt or a visible failure/authorization state. Organization must never recopy or replace the local clipboard automatically.

- [ ] **Step 5: Record the result without promoting unrelated gates**

Update the acceptance evidence with exact build/hash and observations. Keep M09, M10, VoiceOver, reachable-history, merge, push, and release separate.
