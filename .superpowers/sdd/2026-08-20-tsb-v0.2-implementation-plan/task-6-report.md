# Task 6 report: horizontal TSB island

## Outcome

The screen-wide passive notch overlay is now a compact, interactive, nonactivating island. It stays at the top of the built-in notched display when one exists, otherwise falls back to the main display with a fixed safe top inset. The island presents recording, local delivery, organization progress, organized chambers, retained latest results, and recoverable failures without owning recording, storage, networking, or secrets.

The implementation uses the existing `AppSnapshot`, `OrganizationIntent`, `SessionCoordinator`, AppKit panel, and SwiftUI view flow. No dependency, screen-wide click shield, automatic organized-result copy, or Task 7/8 work was added.

## Minimal API ruling

Task 5 intentionally exposes a `SessionID` only on `SecondaryProcessingSnapshot`; the main `AppSnapshot` also does not expose the persisted raw `originalText` separately from its delivered preview.

- For main-session intents, `AppController` captures the session ID already supplied to its existing `startRecording` dependency and uses it only as the coordinator target.
- For a completed secondary result, `NotchOverlayPanel` projects the existing secondary snapshot into an `IslandPresentation` with that explicit secondary `SessionID`. Cancel, retry, and explicit link enrichment therefore cannot be misrouted to a newer main session.
- The original chamber displays the immutable local delivered preview already present in `AppSnapshot` (the coordinator's local cleaned text). It does not pull a record through `TranscriptStore`. Showing the separately persisted raw ASR original later requires a small snapshot projection from a future task; adding store ownership to the UI would violate the current boundary.

This ruling changes no Task 5 domain or persistence type. Its remaining product cost is that Task 6 cannot distinguish raw ASR original text from local reviewed text in the original chamber.

## TDD evidence

### Regeneration and initial RED

The Xcode project was regenerated before the first RED run:

```bash
xcodegen generate --spec apps/macos/TSB/project.yml
```

Then the brief's focused command was run after adding presentation, frame, and generation tests:

```bash
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:TSBTests/OverlayGenerationTests \
  -only-testing:TSBTests/IslandPresentationTests \
  -only-testing:TSBTests/IslandFrameTests test
```

Result: `** TEST FAILED **`, exit 65. The build failed at `OverlayGenerationTests.swift:20` with `extra argument 'onIntent' in call`, proving the required interactive-panel interface did not exist.

### Focused behavioral RED/GREEN cycles

- `testDeliveryDoesNotAutoHideWhileAnOlderOrganizationIsRunning`
  - RED: one test, one failure; `XCTAssertNil` received `1.2`.
  - GREEN: auto-hide now waits while queued/organizing secondary work remains.
- `testSuccessfulDeliveryCollapsesToVisibleIdleSoLatestCanBeReopened`
  - RED interface pass: build failed because `presentedMode` did not exist.
  - RED behavior pass: one test, two failures; the callback made the panel invisible and left mode as `localDelivered`.
  - GREEN: a generation-valid callback returns to visible `120 x 30` idle; a stale callback still cannot replace a newer recording.
- `testDeliveryDoesNotAutoHideWhileAnOlderLocalTranscriptIsRunning`, `testSuggestionsStayLocalUntilGenerateLinksIsExplicitlyActivated`, and `testCompletedSecondaryResultIsRetainedWithItsOwnSessionID`
  - RED: build failed because the target-session presentation/intent surface and retained secondary-session projection did not exist.
  - GREEN: local transcript work also prevents auto-hide; display-only suggestions emit no intent until explicit selection/generation; retained secondary actions carry their owning session ID.
- `testDeliveryWarningsNeverUseSuccessToneOrAutoHide`
  - RED: one test, two failures; both warning samples were incorrectly marked `success`.
  - GREEN: only the exact successful local-copy message receives success tone and the 1.2-second collapse.

### Final GREEN

The brief's exact focused command was rerun after the final production edit.

Result: `** TEST SUCCEEDED **`; 20 tests, 0 failures:

- `IslandFrameTests`: 4/4
- `IslandPresentationTests`: 12/12
- `OverlayGenerationTests`: 4/4

Full suite:

```bash
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

Result: `** TEST SUCCEEDED **`; 192 tests, 0 failures in 20.447 seconds.

## Design and interaction mapping

| Requirement | Implementation and evidence |
| --- | --- |
| Compact, interactive island | `NotchWindow` takes an exact `NSRect`, uses `.nonactivatingPanel`, has mouse events enabled, and never creates a screen-wide window. Frame test verifies the requested frame and style. |
| Notched built-in first; safe fallback | `findScreenForNotch()` selects built-in + notch, otherwise `main`; pure `IslandFrame` tests verify hardware-notch anchoring, fixed 12-point fallback inset, and 12-point visible-screen margins. |
| Candidate sizes and clamp | Pure presentation maps idle to `120 x 30`, live/status to `520 x 82`, and organized to a clamped maximum of `890 x 154`; the frame reducer clamps width and height again to the actual visible frame. |
| Recording | Eight live level bars use the existing bounded `audioLevel`; one-line draft, Stop, and per-session local-only controls emit intents only. Option-Space and Escape wiring remains in `AppController`. |
| Local delivery and organizing | Exact local-copy confirmation is green; warnings remain orange; queued/organizing and older local processing never auto-hide. Stop-waiting and collapse controls remain visible. |
| Organized result | Wide layouts show original, numbered points, and connections simultaneously; narrow layouts show one chamber with a visible segmented picker. |
| Suggestions and privacy | Suggestions render as unchecked local checkboxes. `generateLinks` is disabled until selection and intersects chosen IDs with displayed suggestion IDs before emitting one explicit intent. |
| Gestures and equivalents | Narrow horizontal drag selects the adjacent chamber; the segmented picker is the visible equivalent. Idle downward drag reopens latest; the visible “最近结果” button is the equivalent. Presentation tests require every gesture action to exist in the visible accessible control set. |
| Latest result and concurrency | Success collapse leaves the visible idle island. Main results are retained locally in the panel; completed secondary results are retained with their own session ID. Overlay generations reject stale hide callbacks. |
| VoiceOver and Reduce Motion | Every control has a nonempty accessibility label, status/draft/progress are labelled, and speculative output carries an explicit “推测” chip and combined label. Reduce Motion selects opacity/size transition and disables waveform level animation. |
| Copy boundary | Organized output has manual copy buttons only. `IslandView` emits `.copy(text)`; the only clipboard path is the serial `AppController` manual-copy closure. Organization completion never copies. |

## Files changed

- `apps/macos/TSB/TSB/App/AppController.swift`
- `apps/macos/TSB/TSB/System/Notch/NSScreen+Notch.swift`
- `apps/macos/TSB/TSB/System/Notch/NotchOverlayPanel.swift`
- `apps/macos/TSB/TSB/System/Notch/NotchWindow.swift`
- `apps/macos/TSB/TSB/Views/Notch/IslandPresentation.swift`
- `apps/macos/TSB/TSB/Views/Notch/IslandView.swift`
- `apps/macos/TSB/TSB/Views/Notch/NotchShape.swift`
- `apps/macos/TSB/TSB/Views/Notch/NotchWaveformView.swift`
- `apps/macos/TSB/TSBTests/System/OverlayGenerationTests.swift`
- `apps/macos/TSB/TSBTests/System/IslandPresentationTests.swift`
- `apps/macos/TSB/TSBTests/System/IslandFrameTests.swift`
- `.superpowers/sdd/2026-08-20-tsb-v0.2-implementation-plan/task-6-report.md`

`xcodegen` produced no tracked `project.pbxproj` delta because the existing generated project source groups already discover these files.

## Ponytail self-review and static evidence

- Reused the existing window/panel, snapshots, intents, coordinator, and native AppKit/SwiftUI components. Added no dependency, UI coordinator, state store, recorder wrapper, network client, repository, or screen shield.
- `IslandPresentation` is the only pure UI reducer; `IslandView` owns only ephemeral chamber/suggestion selection state and closures.
- `AppController` serializes island actions through the existing task chain and forwards only `UserIntent`, `OrganizationIntent`, or the explicit manual-copy action.
- UI/system-notch directories contain no `URLSession`, `OrganizationClient`, Keychain, `ClipboardService`, `TranscriptStore`, `AudioRecordingService`, AVAudio, or network reference.
- Static interaction evidence finds native `Button`, `Picker`, `Toggle`, `DragGesture`, VoiceOver labels, Reduce Motion checks, `.nonactivatingPanel`, and `ignoresMouseEvents = false` in the Task 6 files.
- Project/dependency diff scan found no package or dependency change.
- Production credential-pattern scan for common OpenAI/Google/GitHub/AWS literal formats: clean.
- `git diff --check`: exit 0.
- No live provider, real API, real Keychain secret, microphone, or external network was accessed during Task 6 implementation or verification.

## Warnings and concerns

- Xcode continues to emit the existing multiple-matching-destination warning, onnxruntime `Versions/Current` framework-symlink warning, AppIntents metadata-skip warning, and test-host `linkd.autoShortcut` diagnostics. They did not affect focused 20/20 or full 192/192 results.
- Raw persisted `originalText` is not in the current `AppSnapshot`; the original chamber therefore shows the locally reviewed delivered text as ruled above.
- Task 7 owns the settings/authorization screen and Task 8 owns real microphone, visual, VoiceOver, Reduce Motion, offline, and timeout acceptance. This task supplies the controls and static accessibility evidence but deliberately does not perform those tasks.

---

# Fix Round 1 — truthful island actions (2026-08-24)

This section supersedes the earlier concern that `AppSnapshot` lacked raw text. The review explicitly allowed the smallest `AppSnapshot`/`SessionCoordinator` correction, so the island now projects persisted raw `originalText` separately from the locally cleaned preview without adding a UI state layer.

## RED/GREEN evidence

Each finding was driven by its smallest focused `xcodebuild` test before production changes:

| Finding | RED evidence | GREEN evidence |
| --- | --- | --- |
| Raw original vs cleaned preview | `testMainSnapshotSeparatesRawOriginalFromCleanedPreview` failed to compile with `AppSnapshot has no member originalText`; the secondary companion failed with `SecondaryProcessingSnapshot has no member originalText`. | Both 1/1 focused runs passed. Main and secondary snapshots now project `TranscriptRecord.originalText`; the presentation uses raw text for the original chamber and cleaned text for draft/status. |
| Session identity and stale start failure | `testMainSnapshotCarriesItsSessionIdentity` failed to compile because `AppSnapshot` had no `sessionID`. `testFailedNewRecordingDoesNotRetargetOlderResultActions` initially failed to compile because the start-failure seam did not exist. | Focused tests passed. Session-scoped island intents carry non-optional IDs; AppController's optional/current-session fallback was deleted; a failed B start restores coordinator ownership of A while the transient failure snapshot remains unscoped. `testSessionScopedStopCannotStopANewerRecording` also proves a stale stop cannot stop B. |
| One actionable latest result and real route | `testOneLatestTerminalResultSurvivesExpiryUntilANewerResultReplacesIt` failed because the 1.2-second expiry changed `[A]` to `[]`. The production interaction test failed to compile because `NotchOverlayPanel.perform` and `AppController.organizationIntent` did not exist. | Both focused tests passed. The coordinator retains one ordinal-bounded terminal transcript; a newer terminal result releases/removes the older one. A visible dismiss → reopen → retry path crosses the same panel action seam used by `IslandView`, AppController's mapping, and the real coordinator, and still dispatches A after B start fails. |
| Idle visibility and hit testing | `testInitialFallbackIdleIsHiddenWhileHardwareNotchIdleNeverInterceptsClicks` failed to compile before the placement input existed; its reattachment extension then failed because fallback idle became visible again. | The focused test passed. Initial fallback idle with no latest result is hidden; hardware-notch idle may remain at `120 x 30`, but no-action idle always ignores mouse events. A fallback latest result collapses to a visible, interactive “最近结果” button and reopens through the production action seam. |
| Screen changes, real motion choices, visible equivalents | The notification test failed to compile before `ScreenParameterObserver`, `reattach`, and `presentedFrame` existed. The motion test failed to compile before actual `IslandView`/`NotchWaveformView` animation choices were exposed. | Notification-driven reattachment/reposition and observer stop/deinit cleanup passed. `IslandView` reads Reduce Motion and replaces spring with a short ease-out; `NotchWaveformView` removes level animation. Gesture evidence now asserts the concrete visible reopen button and segmented chamber controls instead of a presentation-generated `gestureActions` set. |

Representative RED command shape:

```bash
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:TSBTests/SessionCoordinatorTests/<test-name> test
```

The same shape was used for `IslandPresentationTests` and `OverlayGenerationTests`; every named RED was rerun GREEN before the combined focused gate.

## Invariants and interaction mapping

- Raw source and cleaned preview remain separate through main snapshot, secondary snapshot, presentation, status UI, original chamber, and manual original-copy action.
- `AppSnapshot.sessionID` is optional only for genuinely unscoped idle/start-failure states. Every session-scoped `IslandIntent` contains a concrete `SessionID`; AppController performs no optional target fallback.
- Stop is also coordinator-session-scoped, so an obsolete view cannot toggle a newer recording. Option-Space remains the deliberate current-recording toggle and Escape remains current-recording cancellation.
- Exactly one latest terminal transcript is retained for panel actions. A higher-ordinal result replaces it; an older late organization completion cannot replace the newer slot and becomes removable. Processing capacity continues to count only transcription/saving work.
- `IslandView` sends actions through `NotchOverlayPanel.perform`. The panel accepts only controls visible in the current presentation, handles local dismiss/reopen, and forwards coordinator intents or explicit manual copy.
- Initial fallback idle does not create a persistent click target. Any no-action idle window ignores mouse events; actionable compact/status/result frames are the only interactive region.
- `NSApplication.didChangeScreenParametersNotification` re-runs the existing notched-built-in-first screen selection and reattaches/repositions the same panel. The observer is idempotent, removable on `AppController.stop()`, and self-clearing on deinit.
- Reduce Motion is selected in the actual SwiftUI views, not in a detached presentation enum. The waveform stops animating; island state/size changes use the reduced ease-out path.
- `IslandPresentation.make` is now total/non-optional. The redundant transition enum, `gestureActions`, and external target-session override were deleted.

## Files changed in Fix Round 1

- `apps/macos/TSB/TSB/App/AppController.swift`
- `apps/macos/TSB/TSB/Core/Session/AppSnapshot.swift`
- `apps/macos/TSB/TSB/Core/Session/SessionCoordinator.swift`
- `apps/macos/TSB/TSB/System/Notch/NotchOverlayPanel.swift`
- `apps/macos/TSB/TSB/Views/Notch/IslandPresentation.swift`
- `apps/macos/TSB/TSB/Views/Notch/IslandView.swift`
- `apps/macos/TSB/TSB/Views/Notch/NotchWaveformView.swift`
- `apps/macos/TSB/TSB/Views/PlaceholderView.swift`
- `apps/macos/TSB/TSBTests/Core/Session/SessionCoordinatorTests.swift`
- `apps/macos/TSB/TSBTests/System/IslandPresentationTests.swift`
- `apps/macos/TSB/TSBTests/System/OverlayGenerationTests.swift`
- `.superpowers/sdd/2026-08-20-tsb-v0.2-implementation-plan/task-6-report.md`

## Final verification

Combined focused gate:

```bash
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:TSBTests/OverlayGenerationTests \
  -only-testing:TSBTests/IslandPresentationTests \
  -only-testing:TSBTests/IslandFrameTests \
  -only-testing:TSBTests/SessionCoordinatorTests test
```

Result: `** TEST SUCCEEDED **`; 83 tests, 0 failures (`OverlayGenerationTests` 7, `IslandPresentationTests` 12, `IslandFrameTests` 4, `SessionCoordinatorTests` 60).

The full suite was then run once:

```bash
xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

Result: `** TEST SUCCEEDED **`; 202 tests, 0 failures in 20.631 seconds.

Post-test gates:

- `git diff --check`: exit 0.
- Dependency/project scan: no `Package.swift`, `Package.resolved`, `project.yml`, `project.pbxproj`, Podfile, or Cartfile change.
- UI boundary scan: no URLSession, OrganizationClient, Keychain, ClipboardService, TranscriptStore, AudioRecordingService, AVAudio, or Network reference in the notch UI/system directories.
- Production credential-pattern scan: clean.
- Static behavior/accessibility scan confirms `.nonactivatingPanel`, dynamic `ignoresMouseEvents`, native Button/Picker/Toggle/DragGesture, VoiceOver labels, explicit “推测”, actual Reduce Motion environments, and the native screen-parameter notification.

## Warnings and concerns

- The existing onnxruntime `Versions/Current` framework-symlink warning, AppIntents metadata-skip warning, multiple matching macOS destinations warning, and test-host `linkd.autoShortcut` diagnostics remain non-fatal.
- No new dependency, recorder/store/network ownership in UI, full-screen click shield, live provider call, real API credential, real microphone action, or real Keychain secret access was introduced.
- No unresolved functional concern remains within Fix Round 1 scope; real multi-display/notch hardware and full assistive-technology acceptance remain Task 8's device gate.
