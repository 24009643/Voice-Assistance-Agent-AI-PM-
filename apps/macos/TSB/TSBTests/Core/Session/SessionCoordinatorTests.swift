import AppKit
import Foundation
import Carbon
import XCTest
@testable import TSB

@MainActor
final class SessionCoordinatorTests: XCTestCase {
    func testSuccessfulStopSavesARetainedSuccessRecordAndCopiesExactlyOnce() async throws {
        let harness = CoordinatorHarness(transcript: "原始文本")

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording()
        await harness.waitForDelivery()

        XCTAssertEqual(
            harness.events,
            [.recordingStarted, .recordingFinished, .transcribed, .saved, .copied, .deliveryStatusUpdated]
        )
        XCTAssertEqual(harness.copyCount, 1)
        XCTAssertEqual(harness.deliveryStatuses, [.copied])
        XCTAssertEqual(harness.savedRecords.single?.outcome, .success)
        XCTAssertFalse(harness.audioWasDeleted)
        XCTAssertLessThan(
            try XCTUnwrap(harness.timeline.firstIndex(of: "saved")),
            try XCTUnwrap(harness.timeline.firstIndex(of: "snapshot:delivered"))
        )
        let authorizationAttemptID = try XCTUnwrap(harness.coordinator.snapshot.organizationRequestID)
        XCTAssertEqual(harness.coordinator.snapshot, AppSnapshot(
            sessionID: try XCTUnwrap(harness.startedSessionIDs.single),
            status: .delivered,
            elapsedMilliseconds: 1_000,
            previewText: "原始文本",
            originalText: "原始文本",
            message: "已复制 · 按 ⌘V 粘贴",
            organizationPhase: .authorizationRequired,
            organizationRequestID: authorizationAttemptID
        ))
    }

    func testRepeatedStopAndRepeatedFinishedCallbackDoNotDeliverTwice() async throws {
        let harness = CoordinatorHarness(transcript: "原始文本")

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording()
        await harness.finishRecording()
        await harness.waitForDelivery()

        XCTAssertEqual(harness.stopCount, 1)
        XCTAssertEqual(harness.copyCount, 1)
        XCTAssertEqual(harness.events.filter { $0 == .deliveryStatusUpdated }.count, 1)
    }

    func testInitialSaveFailureKeepsAudioAndDoesNotCopy() async throws {
        let harness = CoordinatorHarness(transcript: "原始文本", saveError: TestError.disk)

        await harness.runOneSession()

        XCTAssertEqual(harness.copyCount, 0)
        XCTAssertFalse(harness.audioWasDeleted)
        XCTAssertEqual(harness.coordinator.snapshot.status, .failed)
    }

    func testCleanupFailureFallsBackToOriginalAfterSave() async throws {
        let harness = CoordinatorHarness(transcript: "原始文本", cleanupError: TestError.cleanup)

        await harness.runOneSession()

        XCTAssertEqual(harness.savedRecords.single?.localCleanedText, "原始文本")
        XCTAssertEqual(harness.copiedTexts, ["原始文本"])
    }

    func testTranscriptionFailureSavesRetainedFailureOutcomeWithoutCopying() async throws {
        let harness = CoordinatorHarness(transcript: "原始文本", transcriptionError: TestError.transcription)

        await harness.runOneSession()

        XCTAssertEqual(harness.savedRecords.single?.outcome, .transcriptionFailed)
        XCTAssertEqual(harness.savedRecords.single?.error, "transcription_failed")
        XCTAssertEqual(harness.copyCount, 0)
        XCTAssertFalse(harness.audioWasDeleted)
        XCTAssertLessThan(
            try XCTUnwrap(harness.timeline.firstIndex(of: "saved")),
            try XCTUnwrap(harness.timeline.firstIndex(of: "snapshot:failed"))
        )
        XCTAssertEqual(harness.coordinator.snapshot.status, .failed)
    }

    func testRecordingFailureSavesRetainedOutcomeBeforeFailedAndNeverTranscribesOrCopies() async throws {
        let harness = CoordinatorHarness(transcript: "原始文本")

        await harness.coordinator.handle(.toggleRecording)
        await harness.failRecording()
        await harness.waitForTerminalState()

        XCTAssertEqual(harness.savedRecords.single?.outcome, .recordingFailed)
        XCTAssertEqual(harness.savedRecords.single?.error, "recording_failed")
        XCTAssertEqual(harness.events.filter { $0 == .transcribed }.count, 0)
        XCTAssertEqual(harness.cancelledPreviewSessionIDs, harness.startedSessionIDs)
        XCTAssertEqual(harness.copyCount, 0)
        XCTAssertFalse(harness.audioWasDeleted)
        XCTAssertLessThan(
            try XCTUnwrap(harness.timeline.firstIndex(of: "saved")),
            try XCTUnwrap(harness.timeline.firstIndex(of: "snapshot:failed"))
        )
        XCTAssertEqual(harness.coordinator.snapshot.status, .failed)
    }

    func testNoSpeechSavesRetainedOutcomeWithoutCopying() async throws {
        let harness = CoordinatorHarness(transcript: "   ")

        await harness.runOneSession()

        XCTAssertEqual(harness.savedRecords.single?.outcome, .noSpeech)
        XCTAssertEqual(harness.savedRecords.single?.localCleanedText, "")
        XCTAssertEqual(harness.copyCount, 0)
        XCTAssertFalse(harness.audioWasDeleted)
        XCTAssertLessThan(
            try XCTUnwrap(harness.timeline.firstIndex(of: "saved")),
            try XCTUnwrap(harness.timeline.firstIndex(of: "snapshot:cancelled"))
        )
        XCTAssertEqual(harness.coordinator.snapshot.status, .cancelled)
    }

    func testClipboardFailurePersistsFailedStatusAndNeverPublishesDelivered() async throws {
        let harness = CoordinatorHarness(transcript: "原始文本", copyResult: false)

        await harness.runOneSession()

        XCTAssertEqual(harness.savedRecords.single?.deliveryStatus, .pending)
        XCTAssertEqual(harness.deliveryStatuses, [.failed])
        XCTAssertEqual(harness.copyCount, 1)
        XCTAssertEqual(harness.coordinator.snapshot.status, .failed)
        XCTAssertNotEqual(harness.coordinator.snapshot.status, .delivered)
    }

    func testCopiedTextWithStatusWriteFailurePublishesWarningAndNeverCopiesAgain() async throws {
        let harness = CoordinatorHarness(transcript: "原始文本", statusWriteError: TestError.disk)

        await harness.runOneSession()
        await harness.finishRecording()
        await Task.yield()

        XCTAssertEqual(harness.savedRecords.count, 1)
        XCTAssertEqual(harness.copyCount, 1)
        XCTAssertEqual(harness.coordinator.snapshot, AppSnapshot(
            sessionID: try XCTUnwrap(harness.startedSessionIDs.single),
            status: .delivered,
            elapsedMilliseconds: 1_000,
            previewText: "原始文本",
            originalText: "原始文本",
            message: "已复制，但未能记录复制状态"
        ))
    }

    func testEscapeCancelsAndDeletesAudioWithoutSavingOrCopying() async throws {
        let harness = CoordinatorHarness(transcript: "原始文本")

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.cancelRecording)

        XCTAssertEqual(harness.cancelCount, 1)
        XCTAssertTrue(harness.audioWasDeleted)
        XCTAssertEqual(harness.cancelledPreviewSessionIDs, harness.startedSessionIDs)
        XCTAssertEqual(harness.cancelledSessionIDs, [try XCTUnwrap(harness.startedSessionIDs.single)])
        XCTAssertTrue(harness.savedRecords.isEmpty)
        XCTAssertEqual(harness.copyCount, 0)
        XCTAssertEqual(harness.coordinator.snapshot.status, .cancelled)
    }

    func testCarbonEscapeCancelsActiveWAVWithoutSavingOrCopying() async throws {
        let harness = CoordinatorHarness(transcript: "原始文本")
        let source = CarbonHotkeyEventSource(keyCode: UInt32(kVK_Escape), modifiers: 0)
        let monitor = EscapeKeyMonitor(eventSource: source)
        monitor.onEscapePressed = {
            Task { @MainActor in
                await harness.coordinator.handle(.cancelRecording)
            }
        }

        await harness.coordinator.handle(.toggleRecording)
        monitor.start()
        source.handle(eventKind: UInt32(kEventHotKeyPressed))
        await Task.yield()
        monitor.stop()

        XCTAssertTrue(harness.audioWasDeleted)
        XCTAssertTrue(harness.savedRecords.isEmpty)
        XCTAssertEqual(harness.copyCount, 0)
    }

    func testCancelAfterFinishedAudioBeforeTranscriptionCompletesDeletesWAVWithoutSavingOrCopying() async throws {
        let harness = CoordinatorHarness(transcript: "原始文本", suspendsTranscription: true)

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording()
        await harness.waitUntilTranscriptionStarts()
        await harness.coordinator.handle(.cancelRecording)
        harness.completeTranscription()
        await Task.yield()

        XCTAssertTrue(harness.audioWasDeleted)
        XCTAssertEqual(harness.cancelledSessionIDs, [try XCTUnwrap(harness.startedSessionIDs.single)])
        XCTAssertEqual(harness.cancelledPreviewSessionIDs, harness.startedSessionIDs)
        XCTAssertTrue(harness.savedRecords.isEmpty)
        XCTAssertEqual(harness.copyCount, 0)
    }

    func testLateAudioCallbackFromCancelledSessionCannotOverwriteNewSession() async throws {
        let harness = CoordinatorHarness(transcript: "原始文本")

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.cancelRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording(at: 0)
        await Task.yield()

        XCTAssertEqual(harness.events.filter { $0 == .transcribed }.count, 0)
        XCTAssertTrue(harness.savedRecords.isEmpty)
        XCTAssertEqual(harness.copyCount, 0)
        XCTAssertEqual(harness.coordinator.snapshot.status, .recording)
    }

    func testLateASRCallbackCannotClearTheNewSessionProcessingOwnership() async throws {
        let harness = CoordinatorHarness(transcript: "原始文本", suspendsTranscription: true)

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording(at: 0)
        await harness.waitUntilTranscriptionStarts(count: 1)
        await harness.coordinator.handle(.cancelRecording)

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording(at: 1)
        await harness.waitUntilTranscriptionStarts(count: 2)
        harness.completeTranscription(at: 0)
        await Task.yield()
        await harness.finishRecording(at: 1)

        XCTAssertEqual(harness.events.filter { $0 == .transcribed }.count, 2)
        XCTAssertTrue(harness.savedRecords.isEmpty)
        XCTAssertEqual(harness.copyCount, 0)
        XCTAssertEqual(harness.coordinator.snapshot.status, .transcribing)
    }

    func testLivePreviewIsVisibleOnlyAndNeverSavesOrCopies() async throws {
        let harness = CoordinatorHarness(transcript: "reviewed")

        await harness.coordinator.handle(.toggleRecording)
        harness.publishPreview("实时内容")
        let publishedSnapshotCount = harness.timeline.count
        harness.publishPreview("实时内容")

        XCTAssertEqual(harness.coordinator.snapshot.status, .recording)
        XCTAssertEqual(harness.coordinator.snapshot.previewText, "实时内容")
        XCTAssertEqual(harness.coordinator.snapshot.message, "实时草稿")
        XCTAssertEqual(harness.timeline.count, publishedSnapshotCount)
        XCTAssertTrue(harness.savedRecords.isEmpty)
        XCTAssertEqual(harness.copyCount, 0)
    }

    func testSenseVoiceSuccessWinsAndPersistsBothCandidates() async throws {
        let harness = CoordinatorHarness(transcript: "SenseVoice final", streamingText: "Paraformer draft")

        await harness.runOneSession()

        XCTAssertEqual(harness.savedRecords.single?.streamingText, "Paraformer draft")
        XCTAssertEqual(harness.savedRecords.single?.senseVoiceText, "SenseVoice final")
        XCTAssertEqual(harness.savedRecords.single?.finalSource, .senseVoice)
        XCTAssertEqual(harness.copiedTexts, ["SenseVoice final"])
    }

    func testSenseVoiceFailureUsesNonemptyCompletedStreamingFallback() async throws {
        let harness = CoordinatorHarness(
            transcript: "ignored",
            streamingText: "Paraformer fallback",
            transcriptionError: TestError.transcription
        )

        await harness.runOneSession()

        XCTAssertEqual(harness.savedRecords.single?.outcome, .success)
        XCTAssertEqual(harness.savedRecords.single?.streamingText, "Paraformer fallback")
        XCTAssertNil(harness.savedRecords.single?.senseVoiceText)
        XCTAssertEqual(harness.savedRecords.single?.finalSource, .streamingFallback)
        XCTAssertEqual(harness.copiedTexts, ["Paraformer fallback"])
    }

    func testSenseVoiceFailureWithoutStreamingResultPersistsFailure() async throws {
        let harness = CoordinatorHarness(transcript: "ignored", transcriptionError: TestError.transcription)

        await harness.runOneSession()

        XCTAssertEqual(harness.savedRecords.single?.outcome, .transcriptionFailed)
        XCTAssertNil(harness.savedRecords.single?.finalSource)
        XCTAssertEqual(harness.copyCount, 0)
    }

    func testSuccessfulEmptySenseVoiceUsesNonemptyStreamingFallback() async throws {
        let harness = CoordinatorHarness(transcript: "   ", streamingText: "Paraformer fallback")

        await harness.runOneSession()

        XCTAssertEqual(harness.savedRecords.single?.outcome, .success)
        XCTAssertEqual(harness.savedRecords.single?.originalText, "Paraformer fallback")
        XCTAssertEqual(harness.savedRecords.single?.finalSource, .streamingFallback)
        XCTAssertEqual(harness.savedRecords.single?.streamingText, "Paraformer fallback")
        XCTAssertEqual(harness.savedRecords.single?.senseVoiceText, "   ")
        XCTAssertEqual(harness.copiedTexts, ["Paraformer fallback"])
    }

    func testControllerStopCancelsEveryIncompleteSession() async throws {
        let harness = CoordinatorHarness(transcript: "late", suspendsTranscription: true)

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording()
        await harness.waitUntilTranscriptionStarts()
        await harness.coordinator.handle(.toggleRecording)
        let incompleteSessionIDs = Set(harness.startedSessionIDs)
        let controller = AppController(state: AppState(), coordinator: harness.coordinator)

        controller.stop()

        XCTAssertEqual(Set(harness.cancelledSessionIDs), incompleteSessionIDs)
        XCTAssertEqual(harness.cancelCount, 2)
        harness.completeTranscription()
        await Task.yield()
    }

    func testBlockedHistoryScanDoesNotBlockANewRecordingIntent() async {
        let harness = CoordinatorHarness(
            transcript: "first result",
            suspendsHistorySuggestions: true
        )

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording()
        await harness.waitUntilHistorySuggestionsStarts()

        await harness.coordinator.handle(.toggleRecording)

        XCTAssertEqual(harness.startedSessionIDs.count, 2)
        XCTAssertEqual(harness.coordinator.snapshot.status, .recording)
        harness.completeHistorySuggestions()
    }

    func testSlowPreviousPreviewFinalizerCannotEraseNextSenseVoiceFallback() async {
        let firstPreview = PipelineOperationsHarness(blockFirstFinish: true)
        let secondPreview = PipelineOperationsHarness()
        var previewSessionIndex = 0
        let pipeline = LivePreviewPipeline(operationsFactory: {
            previewSessionIndex += 1
            return previewSessionIndex == 1 ? firstPreview.operations : secondPreview.operations
        })
        let harness = CoordinatorHarness(
            transcript: "ignored",
            transcriptionError: TestError.transcription,
            livePreviewPipeline: pipeline
        )

        await harness.coordinator.handle(.toggleRecording)
        harness.feedPCM([1], at: 0)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording(at: 0)
        await firstPreview.waitForFirstFinishStart()

        await harness.coordinator.handle(.toggleRecording)
        for value in 1 ... 5 {
            harness.feedPCM([Float(value)], at: 1)
            await Task.yield()
        }
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording(at: 1)
        await harness.waitForDelivery()

        XCTAssertEqual(harness.copiedTexts, ["final:1"])
        XCTAssertEqual(harness.savedRecords.last?.finalSource, .streamingFallback)
        await firstPreview.releaseFirstFinish()
        await harness.waitForDelivery(count: 2)
    }

    func testStalePreviewCannotCrossIntoNewSession() async throws {
        let harness = CoordinatorHarness(transcript: "reviewed")

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.cancelRecording)
        await harness.coordinator.handle(.toggleRecording)
        harness.publishPreview("stale", at: 0)

        XCTAssertEqual(harness.coordinator.snapshot.status, .recording)
        XCTAssertEqual(harness.coordinator.snapshot.previewText, "")
    }

    func testSessionScopedStopCannotStopANewerRecording() async throws {
        let harness = CoordinatorHarness(transcript: "reviewed")

        await harness.coordinator.handle(.toggleRecording)
        let recordingA = try XCTUnwrap(harness.startedSessionIDs.single)
        await harness.coordinator.handle(.cancelRecording)
        await harness.coordinator.handle(.toggleRecording)
        let recordingB = try XCTUnwrap(harness.startedSessionIDs.last)

        harness.coordinator.stopRecording(sessionID: recordingA)
        XCTAssertEqual(harness.stopCount, 0)
        XCTAssertEqual(harness.coordinator.snapshot.sessionID, recordingB)

        harness.coordinator.stopRecording(sessionID: recordingB)
        XCTAssertEqual(harness.stopCount, 1)
    }

    func testNewRecordingOwnsMainWhileOlderSenseVoiceFinishesInSecondaryCard() async throws {
        let harness = CoordinatorHarness(transcript: "first final", suspendsTranscription: true)

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording(at: 0)
        await harness.waitUntilTranscriptionStarts()
        await harness.waitUntilPreviewFinishes()

        await harness.coordinator.handle(.toggleRecording)

        XCTAssertEqual(harness.startedSessionIDs.count, 2)
        XCTAssertEqual(harness.coordinator.snapshot.status, .recording)
        XCTAssertEqual(harness.coordinator.snapshot.secondaryProcessing.count, 1)
        XCTAssertEqual(harness.coordinator.snapshot.secondaryProcessing.single?.status, .transcribing)

        harness.completeTranscription(at: 0)
        await harness.waitForDelivery()

        XCTAssertEqual(harness.coordinator.snapshot.status, .recording)
        XCTAssertEqual(harness.coordinator.snapshot.secondaryProcessing.single?.status, .delivered)
    }

    func testOlderDeliveredSessionStaysAsLatestAfterItsExpiryTimer() async throws {
        let harness = CoordinatorHarness(transcript: "first final", suspendsTranscription: true)

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording(at: 0)
        await harness.waitUntilTranscriptionStarts()

        await harness.coordinator.handle(.toggleRecording)
        harness.publishPreview("new live draft", at: 1)
        harness.completeTranscription(at: 0)
        await harness.waitUntilSecondaryRemovalScheduled()

        XCTAssertEqual(harness.scheduledSecondaryRemovals.single?.delay, 1.2)
        XCTAssertEqual(harness.coordinator.snapshot.status, .recording)
        XCTAssertEqual(harness.coordinator.snapshot.previewText, "new live draft")
        XCTAssertEqual(harness.coordinator.snapshot.secondaryProcessing.single?.status, .delivered)
        XCTAssertEqual(harness.coordinator.snapshot.secondaryProcessing.single?.message, "已复制 · 按 ⌘V 粘贴")

        harness.runScheduledSecondaryRemoval(at: 0)

        XCTAssertEqual(harness.coordinator.snapshot.status, .recording)
        XCTAssertEqual(harness.coordinator.snapshot.previewText, "new live draft")
        XCTAssertEqual(
            harness.coordinator.snapshot.secondaryProcessing.map(\.id),
            [try XCTUnwrap(harness.startedSessionIDs.first)]
        )
    }

    func testOneLatestTerminalResultSurvivesExpiryUntilANewerResultReplacesIt() async throws {
        let harness = CoordinatorHarness(transcript: "retained result")

        await harness.runOneSession()
        let resultA = try XCTUnwrap(harness.coordinator.snapshot.sessionID)
        await harness.coordinator.handle(.toggleRecording)
        await harness.waitUntilSecondaryRemovalScheduled()

        harness.runScheduledSecondaryRemoval(at: 0)
        XCTAssertEqual(harness.coordinator.snapshot.secondaryProcessing.map(\.id), [resultA])

        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording(at: 1)
        await harness.waitForDelivery(count: 2)

        XCTAssertNotEqual(harness.coordinator.snapshot.sessionID, resultA)
        XCTAssertTrue(harness.coordinator.snapshot.secondaryProcessing.isEmpty)
    }

    func testOlderFailedSessionStaysSecondaryWithFailureFeedback() async throws {
        let harness = CoordinatorHarness(
            transcript: "first final",
            suspendsTranscription: true,
            copyResult: false
        )

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording(at: 0)
        await harness.waitUntilTranscriptionStarts()
        await harness.coordinator.handle(.toggleRecording)
        harness.completeTranscription(at: 0)
        await harness.waitUntilSecondaryRemovalScheduled()

        XCTAssertEqual(harness.coordinator.snapshot.status, .recording)
        XCTAssertEqual(harness.coordinator.snapshot.secondaryProcessing.single?.status, .failed)
        XCTAssertEqual(harness.coordinator.snapshot.secondaryProcessing.single?.message, "Could not copy to clipboard.")
    }

    func testSecondaryExpiryRemovesOnlyItsSessionAndPreservesNewerCard() async throws {
        let harness = CoordinatorHarness(transcript: "reviewed", suspendsTranscription: true)

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording(at: 0)
        await harness.waitUntilTranscriptionStarts(count: 1)
        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording(at: 1)
        await harness.waitUntilTranscriptionStarts(count: 2)
        await harness.coordinator.handle(.toggleRecording)

        harness.completeTranscription(at: 0)
        await harness.waitUntilSecondaryRemovalScheduled(count: 1)
        harness.completeTranscription(at: 1)
        await harness.waitUntilSecondaryRemovalScheduled(count: 2)
        let newerSessionID = harness.startedSessionIDs[1]

        harness.runScheduledSecondaryRemoval(at: 0)

        XCTAssertEqual(harness.coordinator.snapshot.status, .recording)
        XCTAssertEqual(harness.coordinator.snapshot.secondaryProcessing.map(\.id), [newerSessionID])
    }

    func testAtMostThreeProcessingSessionsAndCapacityReturnsAfterCompletion() async throws {
        let harness = CoordinatorHarness(transcript: "reviewed", suspendsTranscription: true)

        for index in 0..<3 {
            await harness.coordinator.handle(.toggleRecording)
            await harness.coordinator.handle(.toggleRecording)
            await harness.finishRecording(at: index)
            await harness.waitUntilTranscriptionStarts(count: index + 1)
        }

        XCTAssertFalse(harness.coordinator.snapshot.canStartRecording)
        await harness.coordinator.handle(.toggleRecording)
        XCTAssertEqual(harness.startedSessionIDs.count, 3)

        harness.completeTranscription(at: 0)
        await harness.waitUntilRecordingCapacityReturns()
        await harness.coordinator.handle(.toggleRecording)

        XCTAssertEqual(harness.startedSessionIDs.count, 4)
        XCTAssertEqual(harness.coordinator.snapshot.status, .recording)

        await harness.coordinator.handle(.cancelRecording)
        harness.completeTranscription(at: 1)
        harness.completeTranscription(at: 2)
    }

    func testCancelCleansOnlyCurrentRecordingAndItsPreview() async throws {
        let harness = CoordinatorHarness(transcript: "reviewed")

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.cancelRecording)

        XCTAssertEqual(harness.cancelledPreviewSessionIDs, harness.startedSessionIDs)
        XCTAssertEqual(harness.cancelledSessionIDs, harness.startedSessionIDs)
        XCTAssertTrue(harness.savedRecords.isEmpty)
        XCTAssertEqual(harness.copyCount, 0)
    }

    func testUnavailablePreviewStillDeliversSenseVoiceFinal() async throws {
        let harness = CoordinatorHarness(transcript: "SenseVoice only", streamingText: "")

        await harness.runOneSession()

        XCTAssertEqual(harness.savedRecords.single?.senseVoiceText, "SenseVoice only")
        XCTAssertNil(harness.savedRecords.single?.streamingText)
        XCTAssertEqual(harness.savedRecords.single?.finalSource, .senseVoice)
        XCTAssertEqual(harness.copiedTexts, ["SenseVoice only"])
    }

    func testOrganizationStartsAfterCopiedStatusAndReceivesOnlyCleanedText() async throws {
        let harness = CoordinatorHarness(
            transcript: "original secret source",
            cleanedText: "cleaned organization input",
            organizationSettings: remoteOrganizationSettings()
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationFinishes()

        XCTAssertEqual(harness.organizationInputs.single?.segments.map(\.text), ["cleaned organization input"])
        XCTAssertFalse(harness.organizationInputs.single?.segments.map(\.text).contains("original secret source") == true)
        XCTAssertFalse(harness.organizationInputs.single?.segments.map(\.text).contains(harness.audioURL.path) == true)
        XCTAssertLessThan(try XCTUnwrap(harness.timeline.firstIndex(of: "saved")), try XCTUnwrap(harness.timeline.firstIndex(of: "copied")))
        XCTAssertLessThan(try XCTUnwrap(harness.timeline.firstIndex(of: "copied")), try XCTUnwrap(harness.timeline.firstIndex(of: "delivery:copied")))
        XCTAssertLessThan(try XCTUnwrap(harness.timeline.firstIndex(of: "delivery:copied")), try XCTUnwrap(harness.timeline.firstIndex(of: "organization:pending")))
        XCTAssertLessThan(try XCTUnwrap(harness.timeline.firstIndex(of: "organization:pending")), try XCTUnwrap(harness.timeline.firstIndex(of: "organize")))
        XCTAssertEqual(harness.copyCount, 1)
    }

    func testMainSnapshotSeparatesRawOriginalFromCleanedPreview() async throws {
        let harness = CoordinatorHarness(
            transcript: "raw spoken text",
            cleanedText: "reviewed local text"
        )

        await harness.runOneSession()

        XCTAssertEqual(harness.coordinator.snapshot.previewText, "reviewed local text")
        XCTAssertEqual(harness.coordinator.snapshot.originalText, "raw spoken text")
    }

    func testMainSnapshotCarriesItsSessionIdentity() async throws {
        let harness = CoordinatorHarness(transcript: "identified")

        await harness.coordinator.handle(.toggleRecording)

        XCTAssertEqual(
            harness.coordinator.snapshot.sessionID,
            try XCTUnwrap(harness.startedSessionIDs.single)
        )
    }

    func testSecondarySnapshotKeepsRawOriginalSeparateFromCleanedPreview() async throws {
        let harness = CoordinatorHarness(
            transcript: "raw older text",
            cleanedText: "reviewed older text"
        )

        await harness.runOneSession()
        await harness.coordinator.handle(.toggleRecording)
        let older = try XCTUnwrap(harness.coordinator.snapshot.secondaryProcessing.single)

        XCTAssertEqual(older.previewText, "reviewed older text")
        XCTAssertEqual(older.originalText, "raw older text")
    }

    func testFailedNewRecordingDoesNotRetargetOlderResultActions() async throws {
        let relatedID = SessionID(rawValue: UUID())
        let harness = CoordinatorHarness(
            transcript: "result A",
            startRecordingErrors: [nil, TestError.recordingStart],
            organizationSettings: remoteOrganizationSettings(allowsHistory: true),
            organizationErrors: [TestError.organization, nil, nil],
            historySuggestions: HistorySuggestions(
                suggestedSummaries: [HistorySummaryDTO(candidateID: "h1", summary: "related")],
                localRecordByCandidateID: ["h1": relatedID]
            )
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationFinishes()
        let resultA = try XCTUnwrap(harness.coordinator.snapshot.sessionID)
        let failedRequest = try XCTUnwrap(harness.coordinator.snapshot.organizationRequestID)

        await harness.coordinator.handle(.toggleRecording)
        XCTAssertNil(harness.coordinator.snapshot.sessionID)

        await harness.coordinator.handle(.retry(sessionID: resultA, requestID: failedRequest))
        await harness.waitUntilOrganizationStarts(count: 2)
        XCTAssertEqual(harness.organizationInputs[1].segments.map(\.text), ["result A"])
        await harness.waitUntilOrganizationFinishes()

        await harness.coordinator.handle(.enrichLinks(sessionID: resultA, selectedRecordIDs: [relatedID]))
        await harness.waitUntilOrganizationStarts(count: 3)
        XCTAssertEqual(harness.organizationInputs[2].selectedCandidateIDs, ["h1"])
    }

    func testVisiblePanelRetryRoutesThroughAppControllerMappingToOlderCoordinatorSession() async throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var emittedIntents: [IslandIntent] = []
        let panel = NotchOverlayPanel(screen: screen, onIntent: { emittedIntents.append($0) })
        let harness = CoordinatorHarness(
            transcript: "panel result A",
            startRecordingErrors: [nil, TestError.recordingStart],
            organizationSettings: remoteOrganizationSettings(),
            organizationErrors: [TestError.organization, nil]
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationFinishes()
        let resultA = try XCTUnwrap(harness.coordinator.snapshot.sessionID)
        let failedRequest = try XCTUnwrap(harness.coordinator.snapshot.organizationRequestID)
        panel.update(harness.coordinator.snapshot)

        await harness.coordinator.handle(.toggleRecording)
        panel.update(harness.coordinator.snapshot)
        panel.perform(.dismiss)
        panel.perform(.reopenLatest)
        panel.perform(.retryOrganization(failedRequest))

        let islandIntent = try XCTUnwrap(emittedIntents.last)
        let organizationIntent = try XCTUnwrap(AppController.organizationIntent(for: islandIntent))
        await harness.coordinator.handle(organizationIntent)
        await harness.waitUntilOrganizationStarts(count: 2)

        XCTAssertEqual(harness.organizationInputs[1].segments.map(\.text), ["panel result A"])
        if case let .retry(sessionID, _) = organizationIntent {
            XCTAssertEqual(sessionID, resultA)
        } else {
            XCTFail("Expected retry route")
        }
    }

    func testOrganizationFailureAndRetryNeverCopyAgainAndUseNewRequestID() async throws {
        let harness = CoordinatorHarness(
            transcript: "retry me",
            organizationSettings: remoteOrganizationSettings(),
            organizationErrors: [TestError.organization, nil]
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationFinishes()
        let failedRequestID = try XCTUnwrap(harness.organizationUpdates.last?.organization.requestID)
        let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)

        await harness.coordinator.handle(.retry(sessionID: sessionID, requestID: failedRequestID))
        await harness.waitUntilOrganizationUpdateCount(6)

        XCTAssertEqual(harness.copyCount, 1)
        XCTAssertNotEqual(failedRequestID, harness.organizationUpdates.last?.organization.requestID)
        XCTAssertEqual(harness.organizationUpdates.last?.organization.state, .succeeded)
    }

    func testAuthorizationRequiredPublishesAttemptIDAndRetriesAfterSettingsSaved() async throws {
        let harness = CoordinatorHarness(transcript: "authorize then retry")

        await harness.runOneSession()
        let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
        let unauthorizedAttemptID = try XCTUnwrap(harness.coordinator.snapshot.organizationRequestID)
        XCTAssertEqual(harness.coordinator.snapshot.organizationPhase, .authorizationRequired)

        harness.setOrganizationSettings(remoteOrganizationSettings())
        await harness.coordinator.handle(.retry(sessionID: sessionID, requestID: unauthorizedAttemptID))
        await harness.waitUntilOrganizationFinishes()

        XCTAssertNotEqual(unauthorizedAttemptID, harness.organizationUpdates.last?.organization.requestID)
        XCTAssertEqual(harness.organizationUpdates.last?.organization.state, .succeeded)
    }

    func testInitialPendingWriteFailurePublishesAttemptIDAndCanRetry() async throws {
        let harness = CoordinatorHarness(
            transcript: "persist then retry",
            organizationSettings: remoteOrganizationSettings(),
            organizationWriteFailures: [0]
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationWriteAttemptCount(1)
        let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
        let failedAttemptID = try XCTUnwrap(harness.coordinator.snapshot.organizationRequestID)
        XCTAssertEqual(
            harness.coordinator.snapshot.organizationPhase,
            .failed("Could not save organization state.")
        )

        await harness.coordinator.handle(.retry(sessionID: sessionID, requestID: failedAttemptID))
        await harness.waitUntilOrganizationFinishes()

        XCTAssertNotEqual(failedAttemptID, harness.organizationUpdates.last?.organization.requestID)
        XCTAssertEqual(harness.organizationUpdates.last?.organization.state, .succeeded)
    }

    func testOrganizationDoesNotConsumeASRCapacityAndNewRecordingKeepsOlderOrganizingSession() async throws {
        let harness = CoordinatorHarness(
            transcript: "first",
            organizationSettings: remoteOrganizationSettings(),
            suspendsOrganization: true
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationStarts()
        await harness.coordinator.handle(.toggleRecording)

        XCTAssertEqual(harness.startedSessionIDs.count, 2)
        XCTAssertEqual(harness.coordinator.snapshot.status, .recording)
        XCTAssertTrue(harness.coordinator.snapshot.canStartRecording)
        XCTAssertEqual(harness.coordinator.snapshot.secondaryProcessing.single?.organizationPhase, .organizing)
        XCTAssertTrue(harness.scheduledSecondaryRemovals.isEmpty)

        let olderID = try XCTUnwrap(harness.coordinator.snapshot.secondaryProcessing.single?.id)
        let requestID = try XCTUnwrap(harness.organizationUpdates.last?.organization.requestID)
        await harness.coordinator.handle(.cancel(sessionID: olderID, requestID: requestID))
        harness.completeOrganization()
    }

    func testLateOlderOrganizationPersistsToOlderSessionWithoutReplacingNewMain() async throws {
        let harness = CoordinatorHarness(
            transcript: "older",
            organizationSettings: remoteOrganizationSettings(),
            suspendsOrganization: true
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationStarts()
        let olderID = try XCTUnwrap(harness.startedSessionIDs.single)
        await harness.coordinator.handle(.toggleRecording)
        harness.completeOrganization()
        await harness.waitUntilOrganizationFinishes()

        XCTAssertEqual(harness.organizationUpdates.last?.sessionID, olderID)
        XCTAssertEqual(harness.coordinator.snapshot.status, .recording)
        XCTAssertEqual(harness.coordinator.snapshot.secondaryProcessing.single?.id, olderID)
        guard case .organized = harness.coordinator.snapshot.secondaryProcessing.single?.organizationPhase else {
            return XCTFail("Expected the older organized result in the secondary snapshot")
        }
    }

    func testOrganizedMainExpiryKeepsTheSingleLatestResultActionable() async throws {
        let harness = CoordinatorHarness(
            transcript: "organized before next recording",
            organizationSettings: remoteOrganizationSettings()
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationFinishes()
        await harness.coordinator.handle(.toggleRecording)
        await harness.waitUntilSecondaryRemovalScheduled()

        XCTAssertEqual(harness.scheduledSecondaryRemovals.single?.delay, 1.2)
        guard !harness.scheduledSecondaryRemovals.isEmpty else { return }
        harness.runScheduledSecondaryRemoval(at: 0)
        XCTAssertEqual(harness.coordinator.snapshot.secondaryProcessing.count, 1)
    }

    func testFailedPreparationRearmsSecondaryRemovalWhenOlderTerminalTimerIsPending() async throws {
        let selectedID = SessionID(rawValue: UUID())
        let harness = CoordinatorHarness(
            transcript: "organized before preparation failure",
            organizationSettings: remoteOrganizationSettings(allowsHistory: true)
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationFinishes()
        let organizedSessionID = try XCTUnwrap(harness.startedSessionIDs.single)
        await harness.coordinator.handle(.toggleRecording)
        await harness.waitUntilSecondaryRemovalScheduled()

        harness.setHistorySuggestionsError(TestError.disk)
        await harness.coordinator.handle(.enrichLinks(
            sessionID: organizedSessionID,
            selectedRecordIDs: [selectedID]
        ))
        await Task.yield()

        XCTAssertEqual(harness.scheduledSecondaryRemovals.count, 2)
        guard harness.scheduledSecondaryRemovals.count == 2 else { return }
        harness.runScheduledSecondaryRemoval(at: 0)
        XCTAssertEqual(harness.coordinator.snapshot.secondaryProcessing.single?.id, organizedSessionID)
        harness.runScheduledSecondaryRemoval(at: 1)
        XCTAssertEqual(harness.coordinator.snapshot.secondaryProcessing.single?.id, organizedSessionID)
    }

    func testLocalOnlyFrozenAtStopUsesDeterministicOrganizerAndNeverDispatchesRemote() async throws {
        let harness = CoordinatorHarness(
            transcript: "one sentence.",
            organizationSettings: remoteOrganizationSettings()
        )

        await harness.coordinator.handle(.toggleRecording)
        let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
        await harness.coordinator.handle(.setLocalOnly(sessionID: sessionID, enabled: true))
        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.setLocalOnly(sessionID: sessionID, enabled: false))
        await harness.finishRecording()
        await harness.waitUntilOrganizationFinishes()

        XCTAssertTrue(harness.organizationInputs.isEmpty)
        XCTAssertEqual(harness.organizationUpdates.last?.organization.providerKind, .local)
        XCTAssertEqual(harness.organizationUpdates.last?.organization.output?.numberedPoints.map(\.text), ["one sentence."])
    }

    func testLocalOnlyLoopbackDispatchesToTheLocalModelWithoutLoadingASecret() async throws {
        let harness = CoordinatorHarness(
            transcript: "loopback local-only",
            organizationSettings: loopbackOrganizationSettings()
        )

        await harness.coordinator.handle(.toggleRecording)
        let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
        await harness.coordinator.handle(.setLocalOnly(sessionID: sessionID, enabled: true))
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording()
        await harness.waitUntilOrganizationFinishes()

        XCTAssertEqual(harness.organizationInputs.count, 1)
        XCTAssertEqual(harness.organizationInputs.single?.endpoint.baseURL, URL(string: "http://127.0.0.1:11434/v1/chat/completions"))
        XCTAssertEqual(harness.organizationInputs.single?.apiKey, "")
        XCTAssertEqual(harness.organizationSecretLoadCount, 0)
        XCTAssertEqual(harness.organizationUpdates.last?.organization.providerKind, .local)
    }

    func testCancelOrganizationInvalidatesLateResponseWithoutCancellingCaptureArtifacts() async throws {
        let harness = CoordinatorHarness(
            transcript: "keep delivered text",
            organizationSettings: remoteOrganizationSettings(),
            suspendsOrganization: true
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationStarts()
        let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
        let runningRequestID = try XCTUnwrap(harness.organizationInputs.single?.requestID)

        await harness.coordinator.handle(.cancel(sessionID: sessionID, requestID: runningRequestID))
        let cancelledRequestID = try XCTUnwrap(harness.organizationUpdates.last?.organization.requestID)
        harness.completeOrganization()
        await Task.yield()

        XCTAssertNotEqual(runningRequestID, cancelledRequestID)
        XCTAssertEqual(harness.organizationUpdates.last?.organization.state, .failed)
        XCTAssertEqual(harness.organizationUpdates.last?.organization.errorCode, "cancelled")
        XCTAssertEqual(harness.organizationUpdates.last?.organization.providerKind, .remote)
        XCTAssertEqual(harness.organizationUpdates.last?.organization.model, "test-model")
        XCTAssertEqual(harness.cancelCount, 0)
        XCTAssertFalse(harness.audioWasDeleted)
        XCTAssertEqual(harness.copyCount, 1)
    }

    func testOnlyOneModelRequestRunsWhileLaterSessionIsPersistedPending() async throws {
        let harness = CoordinatorHarness(
            transcript: "queued",
            organizationSettings: remoteOrganizationSettings(),
            suspendsOrganization: true
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationStarts()
        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording(at: 1)
        await harness.waitUntilOrganizationUpdateCount(3)

        XCTAssertEqual(harness.organizationInputs.count, 1)
        XCTAssertEqual(harness.organizationUpdates.map(\.organization.state), [.pending, .pending, .pending])
        XCTAssertTrue(harness.scheduledSecondaryRemovals.isEmpty)

        harness.completeOrganization(at: 0)
        await harness.waitUntilOrganizationStarts(count: 2)
        XCTAssertEqual(harness.organizationInputs.count, 2)
        harness.completeOrganization(at: 1)
        await harness.waitUntilOrganizationFinishes()
    }

    func testCancellingActiveRequestKeepsSlotUntilCancellationInsensitiveCallExits() async throws {
        let harness = CoordinatorHarness(
            transcript: "cancel slot",
            organizationSettings: remoteOrganizationSettings(),
            suspendsOrganization: true
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationStarts()
        let activeSessionID = harness.startedSessionIDs[0]
        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording(at: 1)
        await harness.waitUntilOrganizationUpdateCount(3)

        let activeRequestID = try XCTUnwrap(harness.organizationUpdates.first?.organization.requestID)
        await harness.coordinator.handle(.cancel(sessionID: activeSessionID, requestID: activeRequestID))
        await Task.yield()

        XCTAssertEqual(harness.organizationInputs.count, 1)
        XCTAssertEqual(harness.maximumOrganizationCallCount, 1)
        XCTAssertTrue(harness.scheduledSecondaryRemovals.isEmpty)

        harness.completeOrganization(at: 0)
        await harness.waitUntilOrganizationStarts(count: 2)
        await harness.waitUntilSecondaryRemovalScheduled()
        XCTAssertEqual(harness.maximumOrganizationCallCount, 1)
        harness.completeOrganization(at: 1)
    }

    func testQueuedRequestUsesEndpointConfiguredWhenItsSlotIsClaimed() async throws {
        let endpointA = remoteOrganizationSettings(baseURL: "https://a.example.test/v1/chat/completions")
        let endpointB = remoteOrganizationSettings(baseURL: "https://b.example.test/v1/chat/completions")
        let harness = CoordinatorHarness(
            transcript: "queued settings",
            organizationSettings: endpointA,
            organizationAPIKey: "synthetic-key-for-a",
            suspendsOrganization: true
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationStarts()
        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording(at: 1)
        await harness.waitUntilOrganizationUpdateCount(3)

        harness.setOrganizationDispatch(settings: endpointB, apiKey: "synthetic-key-for-b")
        harness.completeOrganization(at: 0)
        await harness.waitUntilOrganizationStarts(count: 2)

        XCTAssertEqual(harness.organizationInputs[1].endpoint.baseURL.host, "b.example.test")
        XCTAssertEqual(harness.organizationInputs[1].apiKey, "synthetic-key-for-b")
        harness.completeOrganization(at: 1)
    }

    func testQueuedLocalOnlyLoopbackFallsBackWhenSettingsChangeToRemoteBeforeSlot() async throws {
        let remote = remoteOrganizationSettings(baseURL: "https://remote.example.test/v1/chat/completions")
        let harness = CoordinatorHarness(
            transcript: "queued local-only",
            organizationSettings: loopbackOrganizationSettings(),
            suspendsOrganization: true
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationStarts()
        await harness.coordinator.handle(.toggleRecording)
        let localOnlySessionID = try XCTUnwrap(harness.startedSessionIDs.last)
        await harness.coordinator.handle(.setLocalOnly(sessionID: localOnlySessionID, enabled: true))
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording(at: 1)
        await harness.waitUntilOrganizationUpdateCount(3)

        let inputCountBeforeRemoteSettings = harness.organizationInputs.count
        let secretLoadCountBeforeRemoteSettings = harness.organizationSecretLoadCount
        harness.setOrganizationDispatch(settings: remote, apiKey: "must-not-load")
        harness.completeOrganization(at: 0)
        await harness.waitUntilSuccessfulOrganizationCount(2)

        XCTAssertEqual(harness.organizationInputs.count, inputCountBeforeRemoteSettings)
        XCTAssertEqual(harness.organizationSecretLoadCount, secretLoadCountBeforeRemoteSettings)
        XCTAssertEqual(harness.organizationUpdates.last?.sessionID, localOnlySessionID)
        XCTAssertEqual(harness.organizationUpdates.last?.organization.providerKind, .local)
        XCTAssertEqual(harness.organizationUpdates.last?.organization.model, "local-points")
        XCTAssertEqual(harness.organizationUpdates.last?.organization.output?.numberedPoints.map(\.text), ["queued local-only"])
    }

    func testQueuedLocalOnlyRemoteDispatchesToLoopbackWhenSettingsChangeBeforeSlot() async throws {
        let remote = remoteOrganizationSettings(baseURL: "https://remote.example.test/v1/chat/completions")
        let harness = CoordinatorHarness(
            transcript: "queued local-only loopback",
            organizationSettings: remote,
            organizationAPIKey: "remote-key",
            suspendsOrganization: true
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationStarts()
        await harness.coordinator.handle(.toggleRecording)
        let localOnlySessionID = try XCTUnwrap(harness.startedSessionIDs.last)
        await harness.coordinator.handle(.setLocalOnly(sessionID: localOnlySessionID, enabled: true))
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording(at: 1)
        await harness.waitUntilOrganizationUpdateCount(3)

        let inputCountBeforeLoopbackSettings = harness.organizationInputs.count
        let secretLoadCountBeforeLoopbackSettings = harness.organizationSecretLoadCount
        harness.setOrganizationDispatch(settings: loopbackOrganizationSettings(), apiKey: "must-not-load")
        harness.completeOrganization(at: 0)
        for _ in 0..<100 where harness.organizationInputs.count == inputCountBeforeLoopbackSettings {
            await Task.yield()
        }

        XCTAssertEqual(harness.organizationInputs.count, inputCountBeforeLoopbackSettings + 1)
        guard harness.organizationInputs.count == inputCountBeforeLoopbackSettings + 1,
              let loopbackInput = harness.organizationInputs.last else { return }
        XCTAssertEqual(loopbackInput.endpoint.baseURL.host, "127.0.0.1")
        XCTAssertEqual(loopbackInput.apiKey, "")
        XCTAssertEqual(harness.organizationSecretLoadCount, secretLoadCountBeforeLoopbackSettings)
        harness.completeOrganization(at: 1)
        await harness.waitUntilSuccessfulOrganizationCount(2)
        XCTAssertEqual(harness.organizationUpdates.last?.sessionID, localOnlySessionID)
        XCTAssertEqual(harness.organizationUpdates.last?.organization.providerKind, .local)
    }

    func testRevokingConsentBeforeQueuedSlotPreventsItsTextDispatch() async throws {
        let harness = CoordinatorHarness(
            transcript: "must remain local after revoke",
            organizationSettings: remoteOrganizationSettings(),
            suspendsOrganization: true
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationStarts()
        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording(at: 1)
        await harness.waitUntilOrganizationUpdateCount(3)
        let queuedSessionID = harness.startedSessionIDs[1]

        harness.setOrganizationDispatch(settings: OrganizationSettings(), apiKey: "must-not-load")
        harness.completeOrganization(at: 0)
        await harness.waitUntilOrganizationUpdateCount(5)

        XCTAssertEqual(harness.organizationInputs.count, 1)
        XCTAssertEqual(harness.organizationUpdates.last?.sessionID, queuedSessionID)
        XCTAssertEqual(harness.organizationUpdates.last?.organization.state, .failed)
        XCTAssertEqual(harness.organizationUpdates.last?.organization.errorCode, "authorization_required")
        XCTAssertEqual(harness.organizationSecretLoadCount, 1)
    }

    func testRetryInvalidatesOlderRunningCallbackAndUsesFrozenSettingsPerRequest() async throws {
        let firstSettings = remoteOrganizationSettings(model: "first-model")
        let secondSettings = remoteOrganizationSettings(model: "second-model")
        let harness = CoordinatorHarness(
            transcript: "retry while running",
            organizationSettings: firstSettings,
            suspendsOrganization: true
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationStarts()
        let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
        let oldRequestID = try XCTUnwrap(harness.organizationInputs.single?.requestID)
        harness.setOrganizationSettings(secondSettings)
        await harness.coordinator.handle(.retry(sessionID: sessionID, requestID: oldRequestID))
        let retryRequestID = try XCTUnwrap(harness.organizationUpdates.last?.organization.requestID)

        harness.completeOrganization(at: 0)
        await harness.waitUntilOrganizationStarts(count: 2)
        harness.completeOrganization(at: 1)
        await harness.waitUntilOrganizationFinishes()

        XCTAssertNotEqual(oldRequestID, retryRequestID)
        XCTAssertEqual(harness.organizationInputs.map(\.endpoint.model), ["first-model", "second-model"])
        XCTAssertEqual(harness.organizationUpdates.filter { $0.organization.state == .succeeded }.map(\.organization.requestID), [retryRequestID])
        XCTAssertEqual(harness.copyCount, 1)
    }

    func testStaleCancelAndRetryForOlderRequestCannotAffectNewerRequest() async throws {
        let harness = CoordinatorHarness(
            transcript: "stale action",
            organizationSettings: remoteOrganizationSettings(),
            suspendsOrganization: true
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationStarts()
        let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
        let requestA = try XCTUnwrap(harness.organizationUpdates.first?.organization.requestID)

        await harness.coordinator.handle(.retry(sessionID: sessionID, requestID: requestA))
        let requestB = try XCTUnwrap(harness.organizationUpdates.last?.organization.requestID)
        let updateCount = harness.organizationUpdates.count

        await harness.coordinator.handle(.cancel(sessionID: sessionID, requestID: requestA))
        await harness.coordinator.handle(.retry(sessionID: sessionID, requestID: requestA))

        XCTAssertNotEqual(requestA, requestB)
        XCTAssertEqual(harness.organizationUpdates.count, updateCount)

        harness.completeOrganization(at: 0)
        await harness.waitUntilOrganizationStarts(count: 2)
        XCTAssertEqual(harness.organizationInputs[1].requestID, requestB)
        harness.completeOrganization(at: 1)
    }

    func testDevelopmentCleanupRejectsStaleAtomicallyCapturedRequestIdentity() async throws {
        let harness = CoordinatorHarness(
            transcript: "stale cleanup identity",
            organizationSettings: remoteOrganizationSettings(),
            suspendsOrganization: true
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationStarts()
        let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
        let identityA = try XCTUnwrap(harness.coordinator.developmentWorkIdentity(sessionID: sessionID))
        let requestA = try XCTUnwrap(identityA.organizationRequestID)

        await harness.coordinator.handle(.retry(sessionID: sessionID, requestID: requestA))
        let requestB = try XCTUnwrap(harness.organizationUpdates.last?.organization.requestID)

        XCTAssertFalse(harness.coordinator.cancelDevelopmentWork(identityA))
        XCTAssertEqual(harness.coordinator.snapshot.organizationRequestID, requestB)

        harness.completeOrganization(at: 0)
        await harness.waitUntilOrganizationStarts(count: 2)
        XCTAssertEqual(harness.organizationInputs[1].requestID, requestB)
        harness.completeOrganization(at: 1)
    }

    func testLoopbackEndpointDispatchesAsLocalProcessing() async throws {
        let harness = CoordinatorHarness(
            transcript: "loopback",
            organizationSettings: loopbackOrganizationSettings()
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationFinishes()

        XCTAssertEqual(harness.organizationInputs.count, 1)
        XCTAssertEqual(harness.organizationUpdates.last?.organization.providerKind, .local)
    }

    func testCopiedStatusPersistenceFailureDoesNotAutoOrganize() async throws {
        let harness = CoordinatorHarness(
            transcript: "delivered locally",
            statusWriteError: TestError.disk,
            organizationSettings: remoteOrganizationSettings()
        )

        await harness.runOneSession()

        XCTAssertTrue(harness.organizationInputs.isEmpty)
        XCTAssertTrue(harness.organizationUpdates.isEmpty)
        XCTAssertEqual(harness.copyCount, 1)
    }

    func testSuccessfulOrganizationPersistsAndPublishesMainSnapshot() async throws {
        let harness = CoordinatorHarness(
            transcript: "organized main",
            organizationSettings: remoteOrganizationSettings()
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationFinishes()

        XCTAssertEqual(harness.organizationUpdates.map(\.organization.state), [.pending, .pending, .succeeded])
        guard case let .organized(record) = harness.coordinator.snapshot.organizationPhase else {
            return XCTFail("Expected organized main snapshot")
        }
        XCTAssertEqual(record, harness.organizationUpdates.last?.organization)
        XCTAssertEqual(harness.copyCount, 1)
    }

    func testOneHundredSequentialSuccessfulSessionsPreserveEveryDeliveryAndOrganization() async {
        let harness = CoordinatorHarness(
            transcript: "structural cycle",
            organizationSettings: remoteOrganizationSettings()
        )

        for expectedCount in 1...100 {
            await harness.coordinator.handle(.toggleRecording)
            await harness.coordinator.handle(.toggleRecording)
            await harness.finishRecording()
            await harness.waitForDelivery(count: expectedCount)
            let copyCountAtDelivery = harness.copyCount

            await harness.waitUntilSuccessfulOrganizationCount(expectedCount)

            XCTAssertEqual(copyCountAtDelivery, expectedCount)
            XCTAssertEqual(harness.copyCount, copyCountAtDelivery)
            XCTAssertEqual(Set(harness.savedRecords.map(\.id)).count, expectedCount)
            XCTAssertEqual(
                Set(harness.organizationUpdates.filter { $0.organization.state == .succeeded }.map(\.sessionID)).count,
                expectedCount
            )
        }

        let successfulOrganizations = harness.organizationUpdates.filter { $0.organization.state == .succeeded }
        XCTAssertEqual(harness.startedSessionIDs.count, 100)
        XCTAssertEqual(Set(harness.startedSessionIDs).count, 100)
        XCTAssertEqual(harness.savedRecords.count, 100)
        XCTAssertEqual(harness.savedRecords.filter { $0.outcome == .success }.count, 100)
        XCTAssertEqual(Set(harness.savedRecords.map(\.id)), Set(harness.startedSessionIDs))
        XCTAssertEqual(harness.deliveryStatuses, Array(repeating: .copied, count: 100))
        XCTAssertEqual(harness.copyCount, 100)
        XCTAssertEqual(harness.copiedTexts.count, 100)
        XCTAssertEqual(successfulOrganizations.count, 100)
        XCTAssertEqual(Set(successfulOrganizations.map(\.sessionID)), Set(harness.startedSessionIDs))
        XCTAssertTrue(Dictionary(grouping: successfulOrganizations, by: \.sessionID).values.allSatisfy { $0.count == 1 })
        XCTAssertEqual(harness.maximumOrganizationCallCount, 1)
    }

    func testEnrichmentSendsOnlyExactUserSelectedSuggestedRecordIDs() async throws {
        let selectedID = SessionID(rawValue: UUID())
        let unselectedID = SessionID(rawValue: UUID())
        let suggestions = HistorySuggestions(
            suggestedSummaries: [
                HistorySummaryDTO(candidateID: "h1", summary: "selected"),
                HistorySummaryDTO(candidateID: "h2", summary: "not selected")
            ],
            localRecordByCandidateID: ["h1": selectedID, "h2": unselectedID]
        )
        let harness = CoordinatorHarness(
            transcript: "enrich",
            organizationSettings: remoteOrganizationSettings(allowsHistory: true),
            historySuggestions: suggestions
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationFinishes()
        XCTAssertEqual(harness.coordinator.snapshot.suggestedRecords, [
            SuggestedRecordSnapshot(id: selectedID, summary: "selected"),
            SuggestedRecordSnapshot(id: unselectedID, summary: "not selected")
        ])
        let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
        await harness.coordinator.handle(.enrichLinks(sessionID: sessionID, selectedRecordIDs: [selectedID]))
        await harness.waitUntilOrganizationUpdateCount(6)

        XCTAssertEqual(harness.organizationInputs.first?.selectedCandidateIDs, [])
        XCTAssertEqual(harness.organizationInputs.last?.selectedCandidateIDs, ["h1"])
        XCTAssertEqual(harness.organizationUpdates.last?.organization.selectedRecordIDs, [selectedID])
        XCTAssertEqual(harness.organizationUpdates.last?.organization.sentCharacterCount, "enrich".count)
    }

    func testFailedEnrichmentRetryPreservesExactSelectedRecordIDs() async throws {
        let selectedID = SessionID(rawValue: UUID())
        let suggestions = HistorySuggestions(
            suggestedSummaries: [HistorySummaryDTO(candidateID: "h1", summary: "selected")],
            localRecordByCandidateID: ["h1": selectedID]
        )
        let harness = CoordinatorHarness(
            transcript: "retry enrichment",
            organizationSettings: remoteOrganizationSettings(allowsHistory: true),
            organizationErrors: [nil, TestError.organization, nil],
            historySuggestions: suggestions
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationFinishes()
        let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
        await harness.coordinator.handle(.enrichLinks(sessionID: sessionID, selectedRecordIDs: [selectedID]))
        await harness.waitUntilOrganizationStarts(count: 2)
        await harness.waitUntilOrganizationFinishes()
        let failedRequestID = try XCTUnwrap(harness.coordinator.snapshot.organizationRequestID)

        await harness.coordinator.handle(.retry(sessionID: sessionID, requestID: failedRequestID))
        await harness.waitUntilOrganizationStarts(count: 3)
        await harness.waitUntilOrganizationFinishes()

        XCTAssertEqual(harness.organizationInputs[1].selectedCandidateIDs, ["h1"])
        XCTAssertEqual(harness.organizationInputs[2].selectedCandidateIDs, ["h1"])
        XCTAssertEqual(harness.organizationUpdates.last?.organization.selectedRecordIDs, [selectedID])
    }

    func testLaunchMarksPersistedPendingOrganizationInterruptedWithoutRedispatch() throws {
        let pending = makePendingOrganizationRecord()
        let harness = CoordinatorHarness(
            transcript: "unused",
            organizationSettings: remoteOrganizationSettings(),
            persistedRecords: [makeTranscriptRecord(organization: pending)]
        )

        harness.coordinator.recoverInterruptedOrganizations()

        XCTAssertTrue(harness.organizationInputs.isEmpty)
        XCTAssertEqual(harness.organizationUpdates.single?.organization.state, .failed)
        XCTAssertEqual(harness.organizationUpdates.single?.organization.errorCode, "interrupted")
    }

    func testModelFailureWriteErrorDoesNotClaimFailedStateWasPersisted() async throws {
        let harness = CoordinatorHarness(
            transcript: "model failure persistence",
            organizationSettings: remoteOrganizationSettings(),
            organizationErrors: [TestError.organization],
            organizationWriteFailures: [2]
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationWriteAttemptCount(3)

        XCTAssertEqual(harness.organizationUpdates.map(\.organization.state), [.pending, .pending])
        XCTAssertEqual(
            harness.coordinator.snapshot.organizationPhase,
            .failed("Organization failed, but could not save failure state.")
        )
    }

    func testCancellationWriteErrorDoesNotClaimCancellationWasPersisted() async throws {
        let harness = CoordinatorHarness(
            transcript: "cancel persistence",
            organizationSettings: remoteOrganizationSettings(),
            suspendsOrganization: true,
            organizationWriteFailures: [2]
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationStarts()
        let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
        let requestID = try XCTUnwrap(harness.organizationUpdates.last?.organization.requestID)

        await harness.coordinator.handle(.cancel(sessionID: sessionID, requestID: requestID))

        XCTAssertEqual(harness.organizationUpdates.map(\.organization.state), [.pending, .pending])
        XCTAssertEqual(
            harness.coordinator.snapshot.organizationPhase,
            .failed("Organization cancelled, but could not save cancellation state.")
        )
        harness.completeOrganization()
    }

    func testLaunchRecoveryWriteErrorSurfacesUnrecoveredPendingState() throws {
        let pending = makePendingOrganizationRecord()
        let harness = CoordinatorHarness(
            transcript: "unused",
            organizationWriteFailures: [0],
            persistedRecords: [makeTranscriptRecord(organization: pending)]
        )

        harness.coordinator.recoverInterruptedOrganizations()

        XCTAssertTrue(harness.organizationUpdates.isEmpty)
        XCTAssertEqual(
            harness.coordinator.snapshot.message,
            "Could not mark interrupted organization as failed."
        )
    }

    func testAudioLevelIsBoundedAndRapidUpdatesAreThrottled() async throws {
        let harness = CoordinatorHarness(transcript: "level")

        await harness.coordinator.handle(.toggleRecording)
        harness.publishAudioLevel(2)
        await Task.yield()
        let snapshotCount = harness.timeline.count
        harness.publishAudioLevel(0.4)
        await Task.yield()

        XCTAssertEqual(harness.coordinator.snapshot.audioLevel, 1)
        XCTAssertEqual(harness.timeline.count, snapshotCount)
    }

    func testNonfiniteAudioLevelPublishesSafeZero() async {
        let harness = CoordinatorHarness(transcript: "level")

        await harness.coordinator.handle(.toggleRecording)
        harness.publishAudioLevel(.nan)
        await Task.yield()

        XCTAssertEqual(harness.coordinator.snapshot.audioLevel, 0)
    }
}

@MainActor
private final class CoordinatorHarness {
    enum Event: Equatable {
        case recordingStarted
        case recordingFinished
        case transcribed
        case saved
        case copied
        case deliveryStatusUpdated
    }

    struct OrganizationInput {
        let endpoint: OrganizationEndpointSettings
        let apiKey: String
        let requestID: UUID
        let segments: [TextSegment]
        let historySuggestions: HistorySuggestions
        let selectedCandidateIDs: Set<String>
    }

    private let transcript: String
    private let cleanedText: String?
    private let streamingText: String
    private let transcriptionError: Error?
    private let saveError: Error?
    private let statusWriteError: Error?
    private let cleanupError: Error?
    private let suspendsTranscription: Bool
    private let suspendsOrganization: Bool
    private let copyResult: Bool
    private let startRecordingErrors: [Error?]
    private var organizationSettings: OrganizationSettings
    private var organizationAPIKey: String
    private let organizationErrors: [Error?]
    private let organizationWriteFailures: Set<Int>
    private let persistedRecords: [TranscriptRecord]
    private let historySuggestions: HistorySuggestions
    private let suspendsHistorySuggestions: Bool
    private let livePreviewPipeline: LivePreviewPipeline?
    private var historySuggestionsError: Error?
    private var onFinished: [((RecordedAudio) -> Void)] = []
    private var onFailed: [((RecordedAudio) -> Void)] = []
    private var onPreview: [(@MainActor (SessionID, String) -> Void)] = []
    private var onLevel: [(@Sendable (Float) -> Void)] = []
    private var pcmFeeds: [LivePreviewPipeline.Feed] = []
    private var transcriptionContinuations: [CheckedContinuation<TranscriptionResult, Error>?] = []
    private var organizationContinuations: [UnsafeContinuation<OrganizationOutput, Never>?] = []
    private var historySuggestionsContinuations: [CheckedContinuation<HistorySuggestions, Error>?] = []
    let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("SessionCoordinatorTests.wav")

    private(set) var events: [Event] = []
    private(set) var stopCount = 0
    private(set) var cancelCount = 0
    private(set) var startedSessionIDs: [SessionID] = []
    private(set) var cancelledSessionIDs: [SessionID] = []
    private(set) var cancelledPreviewSessionIDs: [SessionID] = []
    private(set) var finishedPreviewSessionIDs: [SessionID] = []
    private(set) var audioWasDeleted = false
    private(set) var copyCount = 0
    private(set) var copiedTexts: [String] = []
    private(set) var savedRecords: [TranscriptRecord] = []
    private(set) var deliveryStatuses: [DeliveryStatus] = []
    private(set) var organizationInputs: [OrganizationInput] = []
    private(set) var organizationSecretLoadCount = 0
    private(set) var organizationWriteAttempts: [(sessionID: SessionID, organization: OrganizationRecord)] = []
    private(set) var organizationUpdates: [(sessionID: SessionID, organization: OrganizationRecord)] = []
    private(set) var activeOrganizationCallCount = 0
    private(set) var maximumOrganizationCallCount = 0
    private(set) var timeline: [String] = []
    private(set) var scheduledSecondaryRemovals: [(delay: TimeInterval, action: @MainActor () -> Void)] = []

    private(set) lazy var coordinator = makeCoordinator()

    init(
        transcript: String,
        cleanedText: String? = nil,
        streamingText: String = "",
        transcriptionError: Error? = nil,
        saveError: Error? = nil,
        statusWriteError: Error? = nil,
        cleanupError: Error? = nil,
        suspendsTranscription: Bool = false,
        copyResult: Bool = true,
        startRecordingErrors: [Error?] = [],
        organizationSettings: OrganizationSettings = OrganizationSettings(),
        organizationAPIKey: String = "synthetic-key",
        suspendsOrganization: Bool = false,
        organizationErrors: [Error?] = [],
        organizationWriteFailures: Set<Int> = [],
        persistedRecords: [TranscriptRecord] = [],
        historySuggestions: HistorySuggestions = HistorySuggestions(suggestedSummaries: [], localRecordByCandidateID: [:]),
        historySuggestionsError: Error? = nil,
        suspendsHistorySuggestions: Bool = false,
        livePreviewPipeline: LivePreviewPipeline? = nil
    ) {
        self.transcript = transcript
        self.cleanedText = cleanedText
        self.streamingText = streamingText
        self.transcriptionError = transcriptionError
        self.saveError = saveError
        self.statusWriteError = statusWriteError
        self.cleanupError = cleanupError
        self.suspendsTranscription = suspendsTranscription
        self.copyResult = copyResult
        self.startRecordingErrors = startRecordingErrors
        self.organizationSettings = organizationSettings
        self.organizationAPIKey = organizationAPIKey
        self.suspendsOrganization = suspendsOrganization
        self.organizationErrors = organizationErrors
        self.organizationWriteFailures = organizationWriteFailures
        self.persistedRecords = persistedRecords
        self.historySuggestions = historySuggestions
        self.historySuggestionsError = historySuggestionsError
        self.suspendsHistorySuggestions = suspendsHistorySuggestions
        self.livePreviewPipeline = livePreviewPipeline
    }

    private func makeCoordinator() -> SessionCoordinator {
        SessionCoordinator(
            dependencies: .init(
                startRecording: { [weak self] sessionID, onPreview, onLevel, onFinished, onFailed in
                    let attempt = self?.startedSessionIDs.count ?? 0
                    self?.events.append(.recordingStarted)
                    self?.startedSessionIDs.append(sessionID)
                    if attempt < (self?.startRecordingErrors.count ?? 0),
                       let error = self?.startRecordingErrors[attempt] {
                        throw error
                    }
                    self?.onPreview.append(onPreview)
                    self?.onLevel.append(onLevel)
                    self?.onFinished.append(onFinished)
                    self?.onFailed.append(onFailed)
                    if let pipeline = self?.livePreviewPipeline {
                        self?.pcmFeeds.append(pipeline.start(sessionID: sessionID, onPreview: onPreview))
                    }
                },
                stopRecording: { [weak self] in
                    self?.stopCount += 1
                },
                cancelRecording: { [weak self] sessionID in
                    self?.cancelCount += 1
                    self?.cancelledSessionIDs.append(sessionID)
                    self?.audioWasDeleted = true
                },
                finishPreview: { [weak self] sessionID in
                    self?.finishedPreviewSessionIDs.append(sessionID)
                    if let pipeline = self?.livePreviewPipeline {
                        return await pipeline.finish(sessionID: sessionID)
                    }
                    return self?.streamingText ?? ""
                },
                cancelPreview: { [weak self] sessionID in
                    self?.cancelledPreviewSessionIDs.append(sessionID)
                    await self?.livePreviewPipeline?.cancel(sessionID: sessionID)
                },
                transcribe: { [weak self] _ in
                    guard let self else { throw TestError.deallocated }
                    self.events.append(.transcribed)
                    if let transcriptionError = self.transcriptionError { throw transcriptionError }
                    if self.suspendsTranscription {
                        return try await withCheckedThrowingContinuation { continuation in
                            self.transcriptionContinuations.append(continuation)
                        }
                    }
                    return TranscriptionResult(text: self.transcript, detectedLanguage: "zh", eventTags: [], latencyMilliseconds: 12)
                },
                clean: { [weak self] source in
                    guard let self else { throw TestError.deallocated }
                    if let cleanupError = self.cleanupError { throw cleanupError }
                    return CleanResult(text: self.cleanedText ?? source.trimmingCharacters(in: .whitespacesAndNewlines), edits: [])
                },
                save: { [weak self] record in
                    guard let self else { throw TestError.deallocated }
                    if let saveError = self.saveError { throw saveError }
                    self.events.append(.saved)
                    self.timeline.append("saved")
                    self.savedRecords.append(record)
                },
                updateDeliveryStatus: { [weak self] _, status in
                    if let statusWriteError = self?.statusWriteError { throw statusWriteError }
                    self?.events.append(.deliveryStatusUpdated)
                    self?.deliveryStatuses.append(status)
                    self?.timeline.append("delivery:\(status.rawValue)")
                },
                copy: { [weak self] text in
                    self?.events.append(.copied)
                    self?.copyCount += 1
                    self?.copiedTexts.append(text)
                    self?.timeline.append("copied")
                    return self?.copyResult ?? false
                },
                loadPersistedRecords: { [weak self] in
                    self?.persistedRecords ?? []
                },
                updateOrganization: { [weak self] sessionID, organization in
                    guard let self else { throw TestError.deallocated }
                    let attempt = self.organizationWriteAttempts.count
                    self.organizationWriteAttempts.append((sessionID, organization))
                    if self.organizationWriteFailures.contains(attempt) { throw TestError.disk }
                    self.organizationUpdates.append((sessionID, organization))
                    self.timeline.append("organization:\(organization.state.rawValue)")
                },
                currentOrganizationSettings: { [weak self] in
                    self?.organizationSettings ?? OrganizationSettings()
                },
                historySuggestions: { [weak self] _ in
                    if let error = self?.historySuggestionsError { throw error }
                    if self?.suspendsHistorySuggestions == true {
                        return try await withCheckedThrowingContinuation { continuation in
                            self?.historySuggestionsContinuations.append(continuation)
                        }
                    }
                    return self?.historySuggestions ?? HistorySuggestions(suggestedSummaries: [], localRecordByCandidateID: [:])
                },
                organize: { [weak self] requestID, segments, suggestions, selectedCandidateIDs, localOnly, willDispatch in
                    guard let self else { throw TestError.deallocated }
                    let dispatch = try AppController.makeOrganizationDispatchSnapshot(
                        localOnly: localOnly,
                        selectedCandidateIDs: selectedCandidateIDs,
                        loadSettings: { self.organizationSettings },
                        loadAPIKey: { _ in
                            self.organizationSecretLoadCount += 1
                            return self.organizationAPIKey
                        }
                    )
                    try willDispatch(dispatch.endpoint)
                    let callIndex = self.organizationInputs.count
                    self.organizationInputs.append(OrganizationInput(
                        endpoint: dispatch.endpoint,
                        apiKey: dispatch.apiKey,
                        requestID: requestID,
                        segments: segments,
                        historySuggestions: suggestions,
                        selectedCandidateIDs: selectedCandidateIDs
                    ))
                    self.timeline.append("organize")
                    self.activeOrganizationCallCount += 1
                    self.maximumOrganizationCallCount = max(
                        self.maximumOrganizationCallCount,
                        self.activeOrganizationCallCount
                    )
                    defer { self.activeOrganizationCallCount -= 1 }
                    if callIndex < self.organizationErrors.count, let error = self.organizationErrors[callIndex] {
                        throw error
                    }
                    if self.suspendsOrganization {
                        return await withUnsafeContinuation { continuation in
                            self.organizationContinuations.append(continuation)
                        }
                    }
                    return makeOrganizationOutput(for: segments)
                },
                scheduleSecondaryRemoval: { [weak self] delay, action in
                    self?.scheduledSecondaryRemovals.append((delay, action))
                }
            ),
            onSnapshot: { [weak self] snapshot in
                self?.timeline.append("snapshot:\(snapshot.status.rawValue)")
            }
        )
    }

    func runOneSession() async {
        await coordinator.handle(.toggleRecording)
        await coordinator.handle(.toggleRecording)
        await finishRecording()
        if saveError == nil,
           transcriptionError == nil,
           statusWriteError == nil,
           !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await waitForDelivery()
        } else {
            await waitForTerminalState()
        }
    }

    func finishRecording(at index: Int? = nil) async {
        events.append(.recordingFinished)
        let callback = index.map { onFinished[$0] } ?? onFinished.last
        callback?(RecordedAudio(url: audioURL, durationMilliseconds: 1_000))
        await Task.yield()
    }

    func publishPreview(_ text: String, at index: Int? = nil) {
        let target = index ?? onPreview.count - 1
        onPreview[target](startedSessionIDs[target], text)
    }

    func publishAudioLevel(_ level: Float, at index: Int? = nil) {
        let target = index ?? onLevel.count - 1
        onLevel[target](level)
    }

    func feedPCM(_ samples: [Float], at index: Int) {
        pcmFeeds[index](samples)
    }

    func setOrganizationSettings(_ settings: OrganizationSettings) {
        organizationSettings = settings
    }

    func setOrganizationDispatch(settings: OrganizationSettings, apiKey: String) {
        organizationSettings = settings
        organizationAPIKey = apiKey
    }

    func setHistorySuggestionsError(_ error: Error?) {
        historySuggestionsError = error
    }

    func waitUntilHistorySuggestionsStarts() async {
        for _ in 0..<100 {
            if !historySuggestionsContinuations.isEmpty { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for history suggestions")
    }

    func completeHistorySuggestions() {
        historySuggestionsContinuations[0]?.resume(returning: historySuggestions)
        historySuggestionsContinuations[0] = nil
    }

    func failRecording(at index: Int? = nil) async {
        let callback = index.map { onFailed[$0] } ?? onFailed.last
        callback?(RecordedAudio(url: audioURL, durationMilliseconds: 500))
        await Task.yield()
    }

    func waitForDelivery(count: Int = 1) async {
        for _ in 0..<100 {
            if deliveryStatuses.count >= count {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for delivery status")
    }

    func waitUntilTranscriptionStarts(count: Int = 1) async {
        for _ in 0..<100 {
            if events.filter({ $0 == .transcribed }).count >= count {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for transcription")
    }

    func waitUntilPreviewFinishes(count: Int = 1) async {
        for _ in 0..<100 {
            if finishedPreviewSessionIDs.count >= count { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for preview finalization")
    }

    func waitUntilSecondaryRemovalScheduled(count: Int = 1) async {
        for _ in 0..<100 {
            if scheduledSecondaryRemovals.count >= count { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for secondary removal scheduling")
    }

    func waitUntilRecordingCapacityReturns() async {
        for _ in 0..<100 {
            if coordinator.snapshot.canStartRecording { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for recording capacity")
    }

    func waitUntilOrganizationStarts(count: Int = 1) async {
        for _ in 0..<100 {
            if organizationInputs.count >= count { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for organization to start")
    }

    func waitUntilOrganizationFinishes() async {
        for _ in 0..<100 {
            if let state = organizationUpdates.last?.organization.state, state != .pending { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for organization to finish")
    }

    func waitUntilSuccessfulOrganizationCount(_ count: Int) async {
        for _ in 0..<100 {
            if organizationUpdates.filter({ $0.organization.state == .succeeded }).count >= count { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for successful organization")
    }

    func waitUntilOrganizationUpdateCount(_ count: Int) async {
        for _ in 0..<100 {
            if organizationUpdates.count >= count { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for organization persistence")
    }

    func waitUntilOrganizationWriteAttemptCount(_ count: Int) async {
        for _ in 0..<100 {
            if organizationWriteAttempts.count >= count { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for organization persistence attempt")
    }

    func completeOrganization(at index: Int = 0) {
        let segments = organizationInputs[index].segments
        organizationContinuations[index]?.resume(returning: makeOrganizationOutput(for: segments))
        organizationContinuations[index] = nil
    }

    func runScheduledSecondaryRemoval(at index: Int) {
        scheduledSecondaryRemovals[index].action()
    }

    func waitForTerminalState() async {
        for _ in 0..<100 {
            if coordinator.snapshot.status != .recording, coordinator.snapshot.status != .transcribing, coordinator.snapshot.status != .saving {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for terminal state")
    }

    func completeTranscription(at index: Int = 0) {
        transcriptionContinuations[index]?.resume(returning: TranscriptionResult(text: transcript, detectedLanguage: "zh", eventTags: [], latencyMilliseconds: 12))
        transcriptionContinuations[index] = nil
    }
}

private enum TestError: Error {
    case disk
    case transcription
    case cleanup
    case organization
    case deallocated
    case recordingStart
}

private func remoteOrganizationSettings(
    baseURL: String = "https://example.test/v1/chat/completions",
    model: String = "test-model",
    allowsHistory: Bool = false
) -> OrganizationSettings {
    OrganizationSettings(
        endpoint: try! OrganizationEndpointSettings(
            baseURL: URL(string: baseURL)!,
            model: model
        ),
        cloudConsentVersion: OrganizationSettings.currentCloudConsentVersion,
        allowUserSelectedHistorySummaries: allowsHistory
    )
}

private func loopbackOrganizationSettings() -> OrganizationSettings {
    OrganizationSettings(
        endpoint: try! OrganizationEndpointSettings(
            baseURL: URL(string: "http://127.0.0.1:11434/v1/chat/completions")!,
            model: "local-model"
        )
    )
}

private func makeOrganizationOutput(for segments: [TextSegment]) -> OrganizationOutput {
    OrganizationOutput(
        noResultReason: segments.isEmpty ? .insufficientContent : nil,
        numberedPoints: segments.enumerated().map {
            NumberedPoint(number: $0.offset + 1, text: $0.element.text, sourceSegmentIDs: [$0.element.id])
        },
        knownRecordLinks: [],
        speculativeConnections: []
    )
}

private func makePendingOrganizationRecord() -> OrganizationRecord {
    OrganizationRecord(
        requestID: UUID(),
        inputTextSHA256: String(repeating: "0", count: 64),
        state: .pending,
        provider: "openai-compatible",
        model: "test-model",
        providerKind: .remote,
        selectedRecordIDs: [],
        output: nil,
        errorCode: nil,
        updatedAt: Date(timeIntervalSince1970: 1)
    )
}

private func makeTranscriptRecord(organization: OrganizationRecord?) -> TranscriptRecord {
    TranscriptRecord(
        id: SessionID(rawValue: UUID()),
        ordinal: SessionOrdinal(rawValue: 1),
        createdAt: Date(timeIntervalSince1970: 1),
        durationMilliseconds: 1_000,
        detectedLanguages: ["zh"],
        originalText: "original",
        localCleanedText: "cleaned",
        edits: [],
        deliveryStatus: .copied,
        outcome: .success,
        finalSource: .senseVoice,
        organization: organization
    )
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
