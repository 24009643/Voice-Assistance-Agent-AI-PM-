# WP-03 Alpha Local Dictation Chain Implementation Plan

**Status:** Approved for execution. G0 passed in `evidence/WP-02-AC-ASR-001-sensevoice-probe.md`; Tasks 1–6 remain sequentially gated by their tests.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the smallest end-to-end macOS Alpha chain: toggle hotkey, local WAV recording, whole-file SenseVoice transcription, conservative deterministic cleanup, atomic original/result save, and exactly one clipboard delivery.

**Architecture:** One `SessionCoordinator` owns lifecycle and delivery. Native AVFoundation records a whole 16 kHz mono WAV; one fixed sherpa-onnx/SenseVoice adapter preserves every frame and transcribes sequential non-overlapping 30-second chunks after stop. Pure cleanup and storage run before a single `NSPasteboard` write. The existing notch/window foundation only reflects immutable state; VAD, push-to-talk, history, retention, API profiles and multi-session overlap remain later work packages.

**Tech Stack:** macOS 14+, Swift 6, SwiftUI, AppKit, AVFoundation, XCTest, XcodeGen, sherpa-onnx 1.13.6, SenseVoiceSmall int8 2024-07-17.

**Spec:** `docs/specs/tsb-v0.1-design.md`

## Global Constraints

- Start implementation only after ADR-0002 is `Accepted` and the G0 evidence records Mandarin, Cantonese, mixed Chinese-English, 3–5 minute and 10 minute hard-gate runs.
- Release bundle identifier is `com.zhuohengchi.tsb`; development identifier is `com.zhuohengchi.tsb.dev`.
- Audio, transcription, cleanup, save and clipboard delivery are local-only. The runtime makes no LLM or cloud-ASR request.
- The original transcript is immutable source data. Cleanup never overwrites it.
- Only `SessionCoordinator` may automatically write the clipboard, and each `SessionID` may auto-deliver at most once.
- Cleanup failure falls back to the original transcript. Save failure preserves the WAV and must not report success. Clipboard failure must not rerun ASR.
- A successful atomic save is required before deleting the temporary WAV.
- Empty recordings create no successful record and do not overwrite the clipboard.
- Models, audio, transcripts, raw metrics, build products and credentials remain Git-ignored.
- No VAD, push-to-talk, multi-session overlap, history UI, retention engine, API settings, signing, installer or public distribution is added in WP-03.

## Mandatory preflight

Before Task 1, the executing agent must verify both conditions and paste the evidence links into `docs/execution/EXE-WP-03.md`:

1. `docs/decisions/ADR-0002-sensevoice-baseline.md` has status `Accepted`.
2. The linked G0 report passes Mandarin, Cantonese, Chinese-English mixed, three 3–5 minute stability runs, one 10 minute stability run, latency/RTF, memory-delta, truncation and privacy checks.

If either condition is false, stop WP-03. Do not create app implementation commits.

---

### Task 1: Freeze Alpha domain contracts and conservative cleanup

**Files:**

- Create: `apps/macos/TSB/TSB/Core/Domain/SessionModels.swift`
- Create: `apps/macos/TSB/TSB/Core/Text/ConservativeCleaner.swift`
- Create: `apps/macos/TSB/TSBTests/Core/Domain/SessionModelsTests.swift`
- Create: `apps/macos/TSB/TSBTests/Core/Text/ConservativeCleanerTests.swift`

**Interfaces:**

- Consumes: Foundation only.
- Produces: `SessionID`, `SessionOrdinal`, `SessionStatus`, `EditOperation`, `CleanResult`, `TranscriptRecord`, and `ConservativeCleaner.clean(_:)`.

- [ ] **Step 1: Write Codable round-trip and source-preservation tests**

```swift
func testTranscriptRecordRoundTripsWithoutOverwritingOriginal() throws {
    let record = TranscriptRecord(
        id: SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
        ordinal: SessionOrdinal(rawValue: 1),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        durationMilliseconds: 1_500,
        detectedLanguages: ["zh"],
        originalText: "嗯 这个想法不能删",
        localCleanedText: "嗯 这个想法不能删",
        edits: [],
        deliveryStatus: .pending
    )
    let decoded = try JSONDecoder().decode(TranscriptRecord.self, from: JSONEncoder().encode(record))
    XCTAssertEqual(decoded, record)
    XCTAssertEqual(decoded.originalText, "嗯 这个想法不能删")
}
```

- [ ] **Step 2: Write cleanup tests for only the Alpha-safe rules**

```swift
func testCleanerNormalizesWhitespaceAndRepeatedPunctuation() {
    let result = ConservativeCleaner().clean("  这个  想法。。不能  改！！  ")
    XCTAssertEqual(result.text, "这个 想法。不能 改！")
    XCTAssertFalse(result.edits.isEmpty)
}

func testCleanerPreservesMeaningBearingContent() {
    let source = "嗯，我不是要删除 2026-08-19，也不是 GPT-5.5"
    XCTAssertEqual(ConservativeCleaner().clean(source).text, source)
}
```

The Alpha cleaner performs only trim, repeated horizontal-whitespace collapse and identical repeated punctuation collapse for `，。！？；：,.!?;:`. It does not remove filler words yet; filler deletion waits for labeled user data.

- [ ] **Step 3: Run the two focused test classes and verify they fail because the types are absent**

```bash
xcodegen generate --spec apps/macos/TSB/project.yml
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:TSBTests/SessionModelsTests \
  -only-testing:TSBTests/ConservativeCleanerTests test
```

- [ ] **Step 4: Implement the minimum contracts**

```swift
struct SessionID: Hashable, Codable, Sendable { let rawValue: UUID }
struct SessionOrdinal: Hashable, Comparable, Codable, Sendable { let rawValue: UInt64 }
enum SessionStatus: String, Codable, Sendable { case idle, recording, transcribing, saving, delivered, failed, cancelled }
enum DeliveryStatus: String, Codable, Sendable { case pending, copied, failed }

struct EditOperation: Equatable, Codable, Sendable {
    enum Kind: String, Codable, Sendable { case trim, whitespace, repeatedPunctuation }
    let kind: Kind
    let startUTF16: Int
    let lengthUTF16: Int
    let original: String
    let replacement: String
}

struct CleanResult: Equatable, Codable, Sendable {
    let text: String
    let edits: [EditOperation]
}
```

`TranscriptRecord` contains exactly the fields used in the test. `SessionOrdinal.<` compares `rawValue`. Cleanup applies deterministic replacements from the end of the source toward the start so UTF-16 offsets remain auditable.

- [ ] **Step 5: Re-run focused tests, then commit**

```bash
git add apps/macos/TSB/TSB/Core/Domain apps/macos/TSB/TSB/Core/Text apps/macos/TSB/TSBTests/Core
git diff --cached --check
git commit -m "feat(domain): add Alpha transcript contracts"
```

### Task 2: Add whole-file local WAV recording

**Files:**

- Create: `apps/macos/TSB/TSB/Core/Audio/AudioRecordingService.swift`
- Create: `apps/macos/TSB/TSBTests/Core/Audio/AudioRecordingServiceTests.swift`

**Interfaces:**

- Consumes: `SessionID`, AVFoundation, an injected temporary-directory URL.
- Produces: `RecordedAudio(url:durationMilliseconds:)`; `start(sessionID:onFinished:)`, `stop()`, and `cancel()`.

- [ ] **Step 1: Write settings and lifecycle tests**

```swift
func testRecordingSettingsAre16kMonoLinearPCM() {
    let settings = AudioRecordingService.recordingSettings
    XCTAssertEqual(settings[AVSampleRateKey] as? Double, 16_000)
    XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 1)
    XCTAssertEqual(settings[AVFormatIDKey] as? UInt32, kAudioFormatLinearPCM)
}

func testCancelRemovesTheActiveSessionWAV() throws {
    let recorder = try recordingServiceWithTemporaryFile()
    try recorder.start(sessionID: fixedSessionID, onFinished: { _ in })
    recorder.cancel()
    XCTAssertFalse(FileManager.default.fileExists(atPath: recorder.activeURL.path))
}
```

- [ ] **Step 2: Run the focused tests and verify missing-type failure**

```bash
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:TSBTests/AudioRecordingServiceTests test
```

- [ ] **Step 3: Implement AVAudioRecorder with a 10-minute safety stop input**

```swift
struct RecordedAudio: Equatable, Sendable {
    let url: URL
    let durationMilliseconds: Int
}

@MainActor
final class AudioRecordingService: NSObject, AVAudioRecorderDelegate {
    static let maximumDuration: TimeInterval = 600
    static let recordingSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16_000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]
}
```

`start` creates `<temp>/TSB/<session UUID>.wav`, enables metering and calls `record(forDuration: 600)`. `audioRecorderDidFinishRecording` invokes `onFinished` exactly once with the completed `RecordedAudio`. Manual `stop` and the delegate callback share one idempotent finalizer, so either route produces one tail-processing event. `cancel` unregisters the callback, stops and deletes the file. No VAD or PCM tap is added here.

Add one test that simulates the delegate's 10-minute completion and proves the callback fires once; a later manual stop must not produce a second `RecordedAudio`.

- [ ] **Step 4: Run focused tests and commit**

```bash
git add apps/macos/TSB/TSB/Core/Audio apps/macos/TSB/TSBTests/Core/Audio
git diff --cached --check
git commit -m "feat(audio): add Alpha WAV recording"
```

### Task 3: Integrate the frozen SenseVoice adapter into the app

**Files:**

- Modify: `apps/macos/TSB/project.yml`
- Create: `apps/macos/TSB/TSB/Core/Transcription/SenseVoiceTranscriber.swift`
- Create: `apps/macos/TSB/TSBTests/Core/Transcription/SenseVoiceTranscriberTests.swift`

**Interfaces:**

- Consumes: `RecordedAudio.url`, sherpa-onnx 1.13.6 and the verified model directory.
- Produces: `TranscriptionResult(text:detectedLanguage:eventTags:latencyMilliseconds:)` through `transcribe(wavURL:) async throws`.

- [ ] **Step 1: Pin the exact package in XcodeGen**

```yaml
packages:
  sherpa-onnx:
    url: https://github.com/k2-fsa/sherpa-onnx
    exactVersion: 1.13.6
```

Add target dependency `package: sherpa-onnx`, product `sherpa-onnx`.

- [ ] **Step 2: Write tests for model-path validation and control-tag separation**

```swift
func testModelLocationRejectsMissingFiles() {
    XCTAssertThrowsError(try SenseVoiceModelLocation(directory: emptyDirectory))
}

func testUserTextDoesNotContainControlTags() {
    let parsed = SenseVoiceTranscriber.parse(text: "这是正文", language: "<|zh|>", event: "<|Speech|>")
    XCTAssertEqual(parsed.text, "这是正文")
    XCTAssertEqual(parsed.detectedLanguage, "zh")
    XCTAssertEqual(parsed.eventTags, ["Speech"])
}
```

- [ ] **Step 3: Run the focused tests and verify red**

```bash
xcodegen generate --spec apps/macos/TSB/project.yml
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:TSBTests/SenseVoiceTranscriberTests test
```

- [ ] **Step 4: Port only the verified probe configuration**

```swift
struct SenseVoiceModelLocation: Sendable {
    let model: URL
    let tokens: URL
    let license: URL
    let manifest: URL
    init(directory: URL) throws
}

struct TranscriptionResult: Equatable, Sendable {
    let text: String
    let detectedLanguage: String?
    let eventTags: [String]
    let latencyMilliseconds: Int
}

actor SenseVoiceTranscriber {
    init(location: SenseVoiceModelLocation) throws
    func transcribe(wavURL: URL) async throws -> TranscriptionResult
    static func parse(text: String, language: String, event: String) -> TranscriptionResult
}
```

For development Alpha, `TSB_SENSEVOICE_MODEL_DIR` must point to the exact G0-approved artifact directory. `SenseVoiceModelLocation` requires `model.int8.onnx`, `tokens.txt`, `LICENSE` and `manifest.sha256`, verifies the manifest before constructing the recognizer, and rejects any digest mismatch. Model installation and distribution remain WP-04 work. The recognizer uses `language="auto"`, `useITN=true`, CPU, one thread and `greedy_search`. WAV validation remains 16 kHz mono. Inputs longer than 30 seconds are split without overlap or dropped frames, decoded sequentially, and joined with newline boundaries; this is not VAD or stable preview. The adapter returns user text separately from normalized language/event tags and never logs transcript text.

Add a digest-mismatch test and, after G0 acceptance, one target-Mac adapter smoke using the approved model and a non-sensitive 16 kHz mono WAV. After adding the package dependency, run `xcodegen generate` followed immediately by a clean app build before proceeding:

```yaml
dependencies:
  - package: sherpa-onnx
    product: sherpa-onnx
```

```bash
xcodegen generate --spec apps/macos/TSB/project.yml
xcodebuild clean build -project apps/macos/TSB/TSB.xcodeproj -scheme TSB \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 5: Run focused tests, the existing probe tests and commit**

```bash
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:TSBTests/SenseVoiceTranscriberTests test
swift test --package-path probes/sensevoice
git add apps/macos/TSB/project.yml apps/macos/TSB/TSB/Core/Transcription apps/macos/TSB/TSBTests/Core/Transcription
git diff --cached --check
git commit -m "feat(asr): add fixed SenseVoice app adapter"
```

### Task 4: Add atomic transcript storage and one clipboard write

**Files:**

- Create: `apps/macos/TSB/TSB/Core/Storage/TranscriptStore.swift`
- Create: `apps/macos/TSB/TSB/Core/Delivery/ClipboardService.swift`
- Create: `apps/macos/TSB/TSBTests/Core/Storage/TranscriptStoreTests.swift`
- Create: `apps/macos/TSB/TSBTests/Core/Delivery/ClipboardServiceTests.swift`

**Interfaces:**

- Consumes: `TranscriptRecord` and delivery text.
- Produces: atomic `<Application Support>/TSB/Sessions/<session UUID>.json` and a Boolean clipboard-write result.

- [ ] **Step 1: Write atomic round-trip and clipboard preservation tests**

```swift
func testSaveRoundTripsARecordAtomically() throws {
    let store = TranscriptStore(directory: try temporaryDirectory())
    try store.save(record)
    XCTAssertEqual(try store.load(id: record.id), record)
}

func testFailedClipboardWriteRestoresExistingItems() {
    let pasteboard = InMemoryPasteboard(items: [.string("previous")])
    pasteboard.failNextWrite = true
    XCTAssertFalse(ClipboardService(pasteboard: pasteboard).copy("new"))
    XCTAssertEqual(pasteboard.items, [.string("previous")])
}
```

- [ ] **Step 2: Run focused tests and verify red**

```bash
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:TSBTests/TranscriptStoreTests \
  -only-testing:TSBTests/ClipboardServiceTests test
```

- [ ] **Step 3: Implement native storage and pasteboard writes**

`TranscriptStore.save` creates the session directory, encodes sorted-key JSON and calls `Data.write(to:options:.atomic)`. `TranscriptStore.updateDeliveryStatus` atomically rewrites the same record after the one clipboard attempt. `ClipboardService.system` snapshots the existing pasteboard items before clearing; if the new string write fails, it restores those items. It never restores after a successful write, synthesizes Command-V or triggers ASR.

Test both post-copy states: `.copied` and `.failed`. A delivery-status update failure leaves the already saved `.pending` record, surfaces the error and never repeats clipboard delivery.

- [ ] **Step 4: Run focused tests and commit**

```bash
git add apps/macos/TSB/TSB/Core/Storage apps/macos/TSB/TSB/Core/Delivery \
  apps/macos/TSB/TSBTests/Core/Storage apps/macos/TSB/TSBTests/Core/Delivery
git diff --cached --check
git commit -m "feat(delivery): persist and copy Alpha results"
```

### Task 5: Wire the Alpha session coordinator and minimal UI state

**Files:**

- Create: `apps/macos/TSB/TSB/Core/Session/SessionCoordinator.swift`
- Create: `apps/macos/TSB/TSB/Core/Session/AppSnapshot.swift`
- Create: `apps/macos/TSB/TSB/App/AppController.swift`
- Modify: `apps/macos/TSB/TSB/App/TSBApp.swift`
- Modify: `apps/macos/TSB/TSB/Views/PlaceholderView.swift`
- Modify: `apps/macos/TSB/TSB/System/HotkeyService.swift`
- Modify: `apps/macos/TSB/TSBTests/System/HotkeyDebounceTests.swift`
- Create: `apps/macos/TSB/TSBTests/Core/Session/SessionCoordinatorTests.swift`

**Interfaces:**

- Consumes: `UserIntent`, recording, transcriber, cleaner, store and clipboard operations.
- Produces: immutable `AppSnapshot(status:elapsedMilliseconds:previewText:message:)` for SwiftUI.

- [ ] **Step 1: Write coordinator tests for the required Alpha outcomes**

```swift
func testSuccessfulStopSavesBeforeOneClipboardDelivery() async throws {
    let harness = CoordinatorHarness(transcript: "原始文本")
    await harness.coordinator.handle(.toggleRecording)
    await harness.coordinator.handle(.toggleRecording)
    XCTAssertEqual(harness.events, [.recordingStarted, .recordingStopped, .transcribed, .saved, .copied])
    XCTAssertEqual(harness.copyCount, 1)
}

func testRepeatedStopDoesNotDeliverTwice() async throws {
    let harness = CoordinatorHarness(transcript: "原始文本")
    await harness.coordinator.handle(.toggleRecording)
    await harness.coordinator.handle(.toggleRecording)
    await harness.coordinator.handle(.toggleRecording)
    XCTAssertEqual(harness.copyCount, 1)
}

func testSaveFailureKeepsAudioAndDoesNotCopy() async throws {
    let harness = CoordinatorHarness(saveError: TestError.disk)
    await harness.runOneSession()
    XCTAssertEqual(harness.copyCount, 0)
    XCTAssertFalse(harness.audioWasDeleted)
}

func testCleanupFailureCopiesOriginalAfterSave() async throws {
    let harness = CoordinatorHarness(transcript: "原始文本", cleanupError: TestError.cleanup)
    await harness.runOneSession()
    XCTAssertEqual(harness.copiedText, "原始文本")
}
```

- [ ] **Step 2: Run the focused tests and verify red**

```bash
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:TSBTests/SessionCoordinatorTests test
```

- [ ] **Step 3: Implement the serialized Alpha state machine**

```swift
struct AppSnapshot: Equatable, Sendable {
    let status: SessionStatus
    let elapsedMilliseconds: Int
    let previewText: String
    let message: String?
}

@MainActor
final class SessionCoordinator {
    struct Dependencies {
        let startRecording: (SessionID, @escaping @Sendable (RecordedAudio) -> Void) throws -> Void
        let stopRecording: () throws -> RecordedAudio
        let cancelRecording: () -> Void
        let transcribe: (URL) async throws -> TranscriptionResult
        let clean: (String) throws -> CleanResult
        let save: (TranscriptRecord) throws -> Void
        let updateDeliveryStatus: (SessionID, DeliveryStatus) throws -> Void
        let copy: (String) -> Bool
        let removeAudio: (URL) throws -> Void
    }

    private(set) var snapshot = AppSnapshot(status: .idle, elapsedMilliseconds: 0, previewText: "", message: nil)
    init(dependencies: Dependencies, onSnapshot: @escaping (AppSnapshot) -> Void)
    func handle(_ intent: UserIntent) async
}
```

Keep the existing `UserIntent` declaration in `HotkeyService.swift`; do not duplicate it. When recording starts, the coordinator passes a callback that re-enters the main actor and handles one internal `.recordingFinished(RecordedAudio)` event. Manual stop and the recorder delegate both call the same idempotent finalization path. The coordinator creates one `SessionID` and increasing ordinal at start. A `stopRequested` latch makes stop idempotent; a `deliveredSessionIDs` set makes automatic clipboard delivery idempotent. After stop it transcribes, cleans with original fallback, atomically saves `.pending`, deletes audio, writes the clipboard once, then atomically updates status to `.copied` or `.failed`. Any initial save error leaves audio in place. Empty text becomes a cancelled/idle outcome without save or copy.

The coordinator test must invoke the injected `onFinished` callback and assert the full event order `[recordingStarted, recordingFinished, transcribed, saved, copied, deliveryStatusUpdated]`; a subsequent manual toggle must not add a second tail or copy event.

- [ ] **Step 4: Wire the existing hotkey, Escape monitor and minimal state UI**

`AppController` owns one coordinator and forwards synchronous hotkey callbacks through `Task { await coordinator.handle(intent) }`; the controller owns and cancels those tasks on shutdown. `PlaceholderView` becomes a native low-fidelity status surface showing idle/recording/processing/result/error text plus a toggle button for development. Use the existing notch/window foundation only for status visibility; do not add history or future buttons. Keep an injectable hotkey event-source seam for existing debounce tests. The production Carbon owner registers Option-Space continuously and registers Escape only while recording; every terminal state unregisters Escape. This lets a session started while another app has focus receive cancellation without Accessibility permission.

Add an integration-level hotkey-source test that starts while the TSB app is not focused, delivers Escape through the production owner's event path, deletes the active WAV, and produces no save or clipboard event.

- [ ] **Step 5: Run focused and full app tests**

```bash
xcodegen generate --spec apps/macos/TSB/project.yml
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

- [ ] **Step 6: Commit**

```bash
git add apps/macos/TSB
git diff --cached --check
git commit -m "feat(alpha): connect local dictation chain"
```

### Task 6: Record Alpha evidence without claiming Beta behavior

**Files:**

- Create: `docs/execution/EXE-WP-03.md`
- Create: `evidence/WP-03-ALPHA-local-chain.md`
- Modify: `docs/README.md`

**Interfaces:**

- Consumes: fresh build/test output and a manual target-Mac smoke with a non-sensitive sentence.
- Produces: traceable Alpha status, exact commit and remaining Beta gaps.

- [ ] **Step 1: Run the final non-interactive verification**

```bash
xcodegen generate --spec apps/macos/TSB/project.yml
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
swift test --package-path probes/sensevoice
git diff --check
```

- [ ] **Step 2: Run one local privacy smoke**

Record a non-sensitive Mandarin/Cantonese/mixed sentence through the app. Confirm one saved record contains separate original and cleaned text, exactly one clipboard delivery occurs, the WAV is removed only after save, and no external network request is initiated by the app.

- [ ] **Step 3: Record exact evidence**

The evidence states whether Alpha passed. It explicitly lists VAD, stable segment preview, push-to-talk, overlapping sessions, custom notch cards, retention, API profile and Golden Set as not implemented.

- [ ] **Step 4: Commit evidence**

```bash
git add docs/execution/EXE-WP-03.md evidence/WP-03-ALPHA-local-chain.md docs/README.md
git diff --cached --check
git commit -m "docs(alpha): record local dictation evidence"
```

## Completion gate

WP-03 may receive tag `tsb-0.1-alpha-pass` only when Tasks 1–6 pass on the target Mac. Failure leaves the branch reviewable but untagged. WP-04 does not start until Alpha evidence passes.
