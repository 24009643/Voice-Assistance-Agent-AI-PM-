import AppKit
import AVFoundation
import Foundation
import Carbon
import XCTest
@testable import TSB

@MainActor
final class SessionCoordinatorTests: XCTestCase {
    func test401KeepsVisibleSentReceiptMetadata() async throws {
        let source = "401 receipt source"
        let summary = "selected private summary"
        let selectedID = SessionID(rawValue: UUID())
        let harness = CoordinatorHarness(
            transcript: source,
            organizationSettings: remoteOrganizationSettings(allowsHistory: true),
            organizationErrors: [nil, OrganizationClientError.httpStatus(401)],
            historySuggestions: HistorySuggestions(
                suggestedSummaries: [HistorySummaryDTO(candidateID: "h1", summary: summary)],
                localRecordByCandidateID: ["h1": selectedID]
            )
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationFinishes()
        let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
        await harness.coordinator.handle(.enrichLinks(
            sessionID: sessionID,
            selectedRecordIDs: [selectedID]
        ))
        await harness.waitUntilOrganizationStarts(count: 2)
        await harness.waitUntilOrganizationUpdateCount(6)

        assertReceipt(
            try XCTUnwrap(harness.coordinator.snapshot.organizationReceipt),
            dispatch: .sent,
            characterCount: source.count,
            selectedRecordCount: 1,
            forbiddenContent: [source, summary, selectedID.rawValue.uuidString]
        )
    }

    func testTimeoutKeepsVisibleSentReceiptMetadata() async throws {
        let source = "timeout receipt source"
        let harness = CoordinatorHarness(
            transcript: source,
            organizationSettings: remoteOrganizationSettings(),
            organizationErrors: [URLError(.timedOut)]
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationFinishes()

        assertReceipt(
            try XCTUnwrap(harness.coordinator.snapshot.organizationReceipt),
            dispatch: .sent,
            characterCount: source.count,
            selectedRecordCount: 0,
            forbiddenContent: [source]
        )
    }

    func testCancelAfterDispatchKeepsVisibleSentReceiptMetadata() async throws {
        let source = "cancel receipt source"
        let harness = CoordinatorHarness(
            transcript: source,
            organizationSettings: remoteOrganizationSettings(),
            suspendsOrganization: true
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationStarts()
        let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
        let requestID = try XCTUnwrap(harness.organizationInputs.single?.requestID)
        await harness.coordinator.handle(.cancel(sessionID: sessionID, requestID: requestID))

        assertReceipt(
            try XCTUnwrap(harness.coordinator.snapshot.organizationReceipt),
            dispatch: .sent,
            characterCount: source.count,
            selectedRecordCount: 0,
            forbiddenContent: [source]
        )
        harness.completeOrganization()
    }

    func testNoDispatchReceiptsReportNoSend() async throws {
        let blockedSource = "authorization receipt source"
        let blocked = CoordinatorHarness(transcript: blockedSource)
        await blocked.runOneSession()

        assertReceipt(
            try XCTUnwrap(blocked.coordinator.snapshot.organizationReceipt),
            dispatch: .notSent,
            characterCount: blockedSource.count,
            selectedRecordCount: 0,
            forbiddenContent: [blockedSource]
        )

        let preflightSource = "preflight receipt source"
        let preflight = CoordinatorHarness(
            transcript: preflightSource,
            organizationSettings: remoteOrganizationSettings(allowsHistory: true),
            historySuggestionsError: TestError.disk
        )
        await preflight.runOneSession()
        await preflight.waitUntilOrganizationFinishes()
        await preflight.coordinator.handle(.enrichLinks(
            sessionID: try XCTUnwrap(preflight.startedSessionIDs.single),
            selectedRecordIDs: [SessionID(rawValue: UUID())]
        ))

        assertReceipt(
            try XCTUnwrap(preflight.coordinator.snapshot.organizationReceipt),
            dispatch: .notSent,
            characterCount: preflightSource.count,
            selectedRecordCount: 0,
            forbiddenContent: [preflightSource]
        )
    }

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
            organizationRequestID: authorizationAttemptID,
            organizationReceipt: OrganizationPrivacyReceipt(
                dispatch: .notSent,
                characterCount: "原始文本".count,
                selectedRecordCount: 0
            ),
            polishState: .notRequested,
            deliverySource: .local
        ))
    }

    func testAcceptedPolishSavesThenCopiesOnceAndDeadlineCannotRecopy() async throws {
        try await withTemporarySessionsRoot { root in
            let clock = ManualContinuousClock()
            let harness = CoordinatorHarness(
                transcript: "use T S B",
                organizationSettings: polishSettings(),
                suspendsPolish: true,
                saveClockAdvances: [1: .milliseconds(50)],
                copyClockAdvance: .milliseconds(25),
                continuousClock: clock,
                sessionsDirectory: root
            )

            await harness.coordinator.handle(.toggleRecording)
            await harness.coordinator.handle(.toggleRecording)
            clock.advance(by: .milliseconds(600))
            await harness.finishRecording()
            await harness.waitUntilPolishStarts()
            await harness.waitUntilPolishDeadlineStarts()
            clock.advance(by: .milliseconds(100))
            let polished = "use TSB"
            harness.completePolish(.accepted(baseCandidateID: .offline, text: polished, edits: []))
            await harness.waitForDelivery()
            let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
            let saveCount = harness.savedRecords.count

            XCTAssertEqual(harness.polishInputs.count, 1)
            XCTAssertEqual(saveCount, 2)
            XCTAssertEqual(harness.savedRecords.last?.polish?.state, .accepted)
            XCTAssertEqual(harness.copiedTexts, [polished])
            XCTAssertEqual(harness.deliveryReceipts.single?.source, .polished)
            XCTAssertEqual(harness.deliveryReceipts.single?.stopToLocalFinalMilliseconds, 600)
            XCTAssertEqual(harness.deliveryReceipts.single?.stopToCopyMilliseconds, 775)
            XCTAssertLessThan(try XCTUnwrap(harness.timeline.firstIndex(of: "saved")), try XCTUnwrap(harness.timeline.lastIndex(of: "saved")))
            XCTAssertLessThan(try XCTUnwrap(harness.timeline.lastIndex(of: "saved")), try XCTUnwrap(harness.timeline.firstIndex(of: "copied")))
            XCTAssertEqual(try harness.store?.load(id: sessionID).deliveredText, polished)

            await harness.firePolishDeadline()
            for _ in 0..<20 { await Task.yield() }

            XCTAssertEqual(harness.savedRecords.count, saveCount)
            XCTAssertEqual(harness.copyCount, 1)
            XCTAssertEqual(try harness.store?.load(id: sessionID).deliveredText, polished)
        }
    }

    func testDelayedDeadlineTaskStartSleepsOnlyUntilLocalSaveDeadline() async {
        let clock = ManualContinuousClock()
        let harness = CoordinatorHarness(
            transcript: "deadline anchored to save",
            organizationSettings: polishSettings(),
            suspendsPolish: true,
            polishStartClockAdvance: .milliseconds(700),
            continuousClock: clock
        )

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording()
        await harness.waitUntilPolishStarts()
        await harness.waitUntilPolishDeadlineStarts(expectedDuration: .milliseconds(800))

        XCTAssertEqual(harness.polishInputs.count, 1)
        XCTAssertEqual(harness.savedRecords.count, 1)
    }

    func testDeadlineTaskStartingAfterSavedDeadlineFallsBackWithoutSleeping() async throws {
        let harness = CoordinatorHarness(
            transcript: "already past deadline",
            organizationSettings: polishSettings(),
            suspendsPolish: true,
            polishStartClockAdvance: .milliseconds(1_600)
        )

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording()
        await harness.waitForDelivery()
        let timedOut = try XCTUnwrap(harness.savedRecords.last?.polish)
        let requestedDurations = await harness.requestedPolishDeadlineDurations()

        XCTAssertEqual(harness.polishInputs.count, 1)
        XCTAssertEqual(requestedDurations, [])
        XCTAssertEqual(timedOut.state, .timedOut)
        XCTAssertEqual(timedOut.elapsedMilliseconds, 1_600)
        XCTAssertEqual(harness.copiedTexts, ["already past deadline"])
    }

    func testDeadlineCopiesDurableLocalOnceAndLatePolishCannotSaveOrRecopy() async throws {
        try await withTemporarySessionsRoot { root in
            let clock = ManualContinuousClock()
            let harness = CoordinatorHarness(
                transcript: "durable local",
                organizationSettings: polishSettings(),
                suspendsPolish: true,
                continuousClock: clock,
                sessionsDirectory: root
            )

            await harness.runUntilPolishStarts()
            clock.advance(by: .milliseconds(1_500))
            await harness.firePolishDeadline()
            await harness.waitForDelivery()
            let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
            let saveCount = harness.savedRecords.count
            let timedOut = try XCTUnwrap(try harness.store?.load(id: sessionID).polish)

            XCTAssertEqual(harness.polishInputs.count, 1)
            XCTAssertEqual(saveCount, 2)
            XCTAssertEqual(harness.copiedTexts, ["durable local"])
            XCTAssertEqual(harness.deliveryReceipts.single?.source, .local)
            XCTAssertEqual(timedOut.state, .timedOut)
            XCTAssertEqual(timedOut.provider, "openai-compatible")
            XCTAssertEqual(timedOut.model, "polish-model")
            XCTAssertEqual(timedOut.providerKind, .remote)
            XCTAssertEqual(timedOut.sentCharacterCount, "durable local".count)
            XCTAssertEqual(timedOut.elapsedMilliseconds, 1_500)
            XCTAssertLessThan(try XCTUnwrap(harness.timeline.firstIndex(of: "saved")), try XCTUnwrap(harness.timeline.firstIndex(of: "copied")))

            harness.completePolish(.accepted(baseCandidateID: .offline, text: "late polish", edits: []))
            for _ in 0..<20 { await Task.yield() }

            XCTAssertEqual(harness.savedRecords.count, saveCount)
            XCTAssertEqual(harness.copyCount, 1)
            XCTAssertEqual(try harness.store?.load(id: sessionID).polish, timedOut)
            XCTAssertEqual(try harness.store?.load(id: sessionID).deliveredText, "durable local")
        }
    }

    func testPhysicallyLateSuccessLosesBeforeDeadlineCallbackRuns() async throws {
        let clock = ManualContinuousClock()
        let harness = CoordinatorHarness(
            transcript: "physical local",
            organizationSettings: polishSettings(),
            suspendsPolish: true,
            continuousClock: clock
        )

        await harness.runUntilPolishStarts()
        clock.advance(by: .milliseconds(1_501))
        harness.completePolish(.accepted(baseCandidateID: .offline, text: "physically late", edits: []))
        await harness.waitForDelivery()
        let timedOut = try XCTUnwrap(harness.savedRecords.last?.polish)

        XCTAssertEqual(harness.polishInputs.count, 1)
        XCTAssertEqual(harness.savedRecords.count, 2)
        XCTAssertEqual(harness.copiedTexts, ["physical local"])
        XCTAssertEqual(harness.deliveryReceipts.single?.source, .local)
        XCTAssertEqual(timedOut.state, .timedOut)
        XCTAssertEqual(timedOut.provider, "openai-compatible")
        XCTAssertEqual(timedOut.model, "polish-model")
        XCTAssertEqual(timedOut.providerKind, .remote)
        XCTAssertEqual(timedOut.sentCharacterCount, "physical local".count)
        XCTAssertEqual(timedOut.elapsedMilliseconds, 1_501)

        await harness.firePolishDeadline()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(harness.copyCount, 1)
    }

    func testPreDispatchNotEligibleFallbackDoesNotClaimTextWasSent() async throws {
        let harness = CoordinatorHarness(transcript: "not eligible stays local")

        await harness.runOneSession()

        XCTAssertEqual(harness.polishInputs.count, 0)
        XCTAssertEqual(harness.savedRecords.count, 1)
        XCTAssertNil(harness.savedRecords.single?.polish)
        XCTAssertEqual(harness.copiedTexts, ["not eligible stays local"])
    }

    func testPreDispatchPolishFailurePersistsUnsentReceiptWithoutDispatchMetadata() async throws {
        let harness = CoordinatorHarness(
            transcript: "pre-dispatch failure stays local",
            polishPreDispatchError: TestError.disk
        )

        await harness.runOneSession()
        let failed = try XCTUnwrap(harness.savedRecords.last?.polish)

        XCTAssertEqual(harness.polishInputs.count, 0)
        XCTAssertEqual(harness.savedRecords.count, 2)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertNil(failed.provider)
        XCTAssertNil(failed.model)
        XCTAssertNil(failed.providerKind)
        XCTAssertNil(failed.sentCharacterCount)
        XCTAssertEqual(failed.errorCode, "polish_failed")
        XCTAssertEqual(harness.copiedTexts, ["pre-dispatch failure stays local"])
    }

    func testFailureAfterWillDispatchPersistsSentDispatchMetadata() async throws {
        let harness = CoordinatorHarness(
            transcript: "post-dispatch failure stays local",
            organizationSettings: polishSettings()
        )

        await harness.runOneSession()
        let failed = try XCTUnwrap(harness.savedRecords.last?.polish)

        XCTAssertEqual(harness.polishInputs.count, 1)
        XCTAssertEqual(harness.savedRecords.count, 2)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.provider, "openai-compatible")
        XCTAssertEqual(failed.model, "polish-model")
        XCTAssertEqual(failed.providerKind, .remote)
        XCTAssertEqual(failed.sentCharacterCount, "post-dispatch failure stays local".count)
        XCTAssertEqual(failed.errorCode, "polish_failed")
        XCTAssertEqual(harness.copiedTexts, ["post-dispatch failure stays local"])
    }

    func testAcceptedPolishSaveFailureFallsBackInsideLeaseAndCopiesLocalOnce() async throws {
        try await withTemporarySessionsRoot { root in
            let harness = CoordinatorHarness(
                transcript: "safe local",
                saveFailures: [1],
                organizationSettings: polishSettings(),
                suspendsPolish: true,
                sessionsDirectory: root
            )

            await harness.runUntilPolishStarts()
            harness.completePolish(.accepted(baseCandidateID: .offline, text: "unsafe unsaved polish", edits: []))
            await harness.waitForDelivery()
            let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)

            XCTAssertEqual(harness.polishInputs.count, 1)
            XCTAssertEqual(harness.copyCount, 1)
            XCTAssertEqual(harness.copiedTexts, ["safe local"])
            XCTAssertEqual(harness.deliveryReceipts.single?.source, .local)
            XCTAssertFalse(harness.savedRecords.contains { $0.polish?.state == .accepted })
            XCTAssertEqual(try harness.store?.load(id: sessionID).deliveredText, "safe local")

            await harness.firePolishDeadline()
            for _ in 0..<20 { await Task.yield() }
            XCTAssertEqual(harness.copyCount, 1)
        }
    }

    func testShutdownAfterLocalSavePreservesRecordAndCreatesNoCopy() async throws {
        try await withTemporarySessionsRoot { root in
            let harness = CoordinatorHarness(
                transcript: "shutdown durable local",
                organizationSettings: polishSettings(),
                suspendsPolish: true,
                sessionsDirectory: root
            )

            await harness.runUntilPolishStarts()
            let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
            harness.coordinator.shutdown()
            harness.completePolish(.accepted(baseCandidateID: .offline, text: "late after shutdown", edits: []))
            await harness.firePolishDeadline()
            for _ in 0..<20 { await Task.yield() }

            XCTAssertEqual(harness.polishInputs.count, 1)
            XCTAssertEqual(harness.savedRecords.count, 1)
            XCTAssertEqual(harness.copyCount, 0)
            XCTAssertEqual(try harness.store?.load(id: sessionID).localCleanedText, "shutdown durable local")
            XCTAssertNil(try harness.store?.load(id: sessionID).polish)
        }
    }

    func testRevokingPolishAfterDispatchCopiesLocalOnceAndRejectsLateCompletion() async throws {
        try await withTemporarySessionsRoot { root in
            let harness = CoordinatorHarness(
                transcript: "durable local after revoke",
                organizationSettings: polishSettings(),
                suspendsPolish: true,
                sessionsDirectory: root
            )

            await harness.runUntilPolishStarts()
            let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
            harness.coordinator.cancelPendingPolishAfterRevoke()
            await harness.waitForDelivery()
            let cancelled = try XCTUnwrap(try harness.store?.load(id: sessionID).polish)
            let saveCount = harness.savedRecords.count

            XCTAssertEqual(harness.polishInputs.count, 1)
            XCTAssertEqual(saveCount, 2)
            XCTAssertEqual(cancelled.state, .cancelled)
            XCTAssertEqual(cancelled.provider, "openai-compatible")
            XCTAssertEqual(cancelled.model, "polish-model")
            XCTAssertEqual(cancelled.providerKind, .remote)
            XCTAssertEqual(cancelled.sentCharacterCount, "durable local after revoke".count)
            XCTAssertEqual(harness.copiedTexts, ["durable local after revoke"])

            harness.completePolish(.accepted(baseCandidateID: .offline, text: "revoked late polish", edits: []))
            await harness.firePolishDeadline()
            for _ in 0..<20 { await Task.yield() }

            XCTAssertEqual(harness.savedRecords.count, saveCount)
            XCTAssertEqual(harness.copyCount, 1)
            XCTAssertEqual(try harness.store?.load(id: sessionID).polish, cancelled)
            XCTAssertEqual(try harness.store?.load(id: sessionID).deliveredText, "durable local after revoke")
        }
    }

    func testPreStopCancelMakesZeroPolishRequestsAndZeroCopies() async throws {
        let harness = CoordinatorHarness(
            transcript: "cancel before stop",
            organizationSettings: polishSettings(),
            suspendsPolish: true
        )

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.cancelRecording)

        XCTAssertEqual(harness.polishInputs.count, 0)
        XCTAssertEqual(harness.copyCount, 0)
        XCTAssertEqual(harness.providerStarts, 0)
    }

    func testLocalOnlyMakesZeroPolishAndOrganizationRequests() async throws {
        let harness = CoordinatorHarness(
            transcript: "local only",
            organizationSettings: polishSettings(),
            suspendsPolish: true
        )

        await harness.coordinator.handle(.toggleRecording)
        let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
        await harness.coordinator.handle(.setLocalOnly(sessionID: sessionID, enabled: true))
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording()
        await harness.waitForDelivery()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(harness.polishInputs.count, 0)
        XCTAssertEqual(harness.organizationInputs.count, 0)
        XCTAssertEqual(harness.organizationUpdates.count, 0)
        XCTAssertEqual(harness.providerStarts, 0)
        XCTAssertEqual(harness.copiedTexts, ["local only"])
    }

    func testOrganizationReceivesExactDeliveredTextAndNeverRecopies() async throws {
        let harness = CoordinatorHarness(
            transcript: "organization local",
            organizationSettings: polishSettings(),
            suspendsPolish: true
        )

        await harness.runUntilPolishStarts()
        harness.completePolish(.accepted(baseCandidateID: .offline, text: "organization polished", edits: []))
        await harness.waitForDelivery()
        let copyCountAtDelivery = harness.copyCount
        await harness.waitUntilOrganizationFinishes()

        XCTAssertEqual(harness.polishInputs.count, 1)
        XCTAssertEqual(harness.organizationInputs.single?.segments.map(\.text), ["organization polished"])
        XCTAssertEqual(harness.copyCount, copyCountAtDelivery)
        XCTAssertLessThan(try XCTUnwrap(harness.timeline.firstIndex(of: "copied")), try XCTUnwrap(harness.timeline.firstIndex(of: "organization:pending")))
        XCTAssertLessThan(try XCTUnwrap(harness.timeline.firstIndex(of: "organization:pending")), try XCTUnwrap(harness.timeline.firstIndex(of: "organize")))

        await harness.firePolishDeadline()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(harness.copyCount, copyCountAtDelivery)
    }

    private func assertReceipt(
        _ receipt: OrganizationPrivacyReceipt,
        dispatch: OrganizationReceiptDispatch,
        characterCount: Int,
        selectedRecordCount: Int,
        forbiddenContent: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(receipt.dispatch, dispatch, file: file, line: line)
        XCTAssertEqual(receipt.characterCount, characterCount, file: file, line: line)
        XCTAssertEqual(receipt.selectedRecordCount, selectedRecordCount, file: file, line: line)
        XCTAssertEqual(
            Set(Mirror(reflecting: receipt).children.compactMap(\.label)),
            ["dispatch", "characterCount", "selectedRecordCount"],
            file: file,
            line: line
        )
        let reflected = String(reflecting: receipt)
        for content in forbiddenContent {
            XCTAssertFalse(reflected.contains(content), file: file, line: line)
        }
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
            message: "已复制，但未能记录复制状态",
            polishState: .notRequested
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

    func testCancelAfterStoppedAudioDuringTranscriptionDoesNotInterruptFinalization() async throws {
        let harness = CoordinatorHarness(transcript: "原始文本", suspendsTranscription: true)

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording()
        await harness.waitUntilTranscriptionStarts()
        await harness.coordinator.handle(.cancelRecording)
        harness.completeTranscription()
        await harness.waitForDelivery()

        XCTAssertFalse(harness.audioWasDeleted)
        XCTAssertTrue(harness.cancelledSessionIDs.isEmpty)
        XCTAssertTrue(harness.cancelledPreviewSessionIDs.isEmpty)
        XCTAssertEqual(harness.savedRecords.single?.outcome, .success)
        XCTAssertEqual(harness.copyCount, 1)
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

    func testOlderASRCompletionCannotClearTheNewSessionProcessingOwnership() async throws {
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
        XCTAssertEqual(harness.savedRecords.count, 1)
        XCTAssertEqual(harness.copyCount, 1)
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

    func testPreviewOverflowMarksOnlyCurrentSessionUnavailableWithoutChangingDraft() async {
        let harness = CoordinatorHarness(transcript: "final")

        await harness.coordinator.handle(.toggleRecording)
        harness.publishPreview("last live draft")
        harness.disableLivePreview()

        XCTAssertEqual(harness.coordinator.snapshot.livePreviewAvailability, .unavailable)
        XCTAssertEqual(harness.coordinator.snapshot.previewText, "last live draft")
        XCTAssertEqual(
            IslandPresentation.make(for: harness.coordinator.snapshot).draft,
            "停止后仍会生成全文"
        )
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

    func testControllerStopDeletesOnlyActiveUnstoppedRecordingAndCancelsProcessingTask() async throws {
        let harness = CoordinatorHarness(transcript: "late", suspendsTranscription: true)

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording()
        await harness.waitUntilTranscriptionStarts()
        let processingSessionID = try XCTUnwrap(harness.startedSessionIDs.last)
        await harness.coordinator.handle(.toggleRecording)
        let activeRecordingID = try XCTUnwrap(harness.startedSessionIDs.last)
        let controller = AppController(state: AppState(), coordinator: harness.coordinator)

        controller.stop()

        XCTAssertEqual(harness.cancelledSessionIDs, [activeRecordingID])
        XCTAssertEqual(harness.cancelCount, 1)
        harness.completeTranscription()
        await Task.yield()
        XCTAssertTrue(harness.savedRecords.isEmpty)
        XCTAssertEqual(harness.copyCount, 0)
        XCTAssertEqual(Set(harness.cancelledPreviewSessionIDs), [processingSessionID, activeRecordingID])
    }

    func testShutdownCancelsDeliveredBlockedHistoryBeforeOrganizationCanStart() async {
        let harness = CoordinatorHarness(
            transcript: "delivered text",
            organizationSettings: remoteOrganizationSettings(),
            suspendsHistorySuggestions: true
        )
        let controller = AppController(state: AppState(), coordinator: harness.coordinator)

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        await harness.finishRecording()
        await harness.waitForDelivery()
        await harness.waitUntilHistorySuggestionsStarts()

        controller.stop()
        harness.completeHistorySuggestions()
        for _ in 0..<100 { await Task.yield() }

        XCTAssertTrue(harness.organizationInputs.isEmpty)
        XCTAssertNil(harness.coordinator.snapshot.sessionID)
        XCTAssertEqual(harness.coordinator.snapshot.status, .idle)
    }

    func testShutdownDuringDeliveredHistoryLoadPreservesDurableRecordAndStartsNoOrganization() async throws {
        try await withTemporarySessionsRoot { root in
            let harness = CoordinatorHarness(
                transcript: "durable delivered text",
                organizationSettings: remoteOrganizationSettings(),
                suspendsHistorySuggestions: true,
                sessionsDirectory: root
            )

            await harness.coordinator.handle(.toggleRecording)
            await harness.coordinator.handle(.toggleRecording)
            await harness.finishRecording()
            await harness.waitForDelivery()
            await harness.waitUntilHistorySuggestionsStarts()
            let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)

            harness.coordinator.shutdown()
            harness.completeHistorySuggestions()
            for _ in 0..<100 { await Task.yield() }

            XCTAssertEqual(try harness.store?.load(id: sessionID).id, sessionID)
            XCTAssertEqual(harness.organizationInputs.count, 0)
            XCTAssertEqual(harness.providerStarts, 0)
            XCTAssertEqual(harness.coordinator.snapshot.status, .idle)
        }
    }

    func testStopThenShutdownPreservesPendingAudioDirectory() async throws {
        try await withTemporarySessionsRoot { root in
            let harness = CoordinatorHarness(
                transcript: "pending finalization",
                suspendsPreviewCancellation: true,
                sessionsDirectory: root
            )

            await harness.coordinator.handle(.toggleRecording)
            let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
            let identity = try XCTUnwrap(harness.coordinator.developmentWorkIdentity(sessionID: sessionID))
            let sessionDirectory = root.appendingPathComponent(sessionID.rawValue.uuidString, isDirectory: true)
            let audioURL = sessionDirectory.appendingPathComponent("audio.wav")
            try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
            try Data("pending audio".utf8).write(to: audioURL)

            await harness.coordinator.handle(.toggleRecording)
            harness.coordinator.shutdown()
            for _ in 0..<100 where !harness.cancelledPreviewSessionIDs.contains(sessionID) {
                await Task.yield()
            }

            XCTAssertEqual(harness.stopCount, 1)
            XCTAssertEqual(try Data(contentsOf: audioURL), Data("pending audio".utf8))
            XCTAssertTrue(FileManager.default.fileExists(atPath: sessionDirectory.path))
            XCTAssertEqual(harness.cancelledPreviewSessionIDs, [sessionID])
            XCTAssertFalse(harness.coordinator.isDevelopmentWorkDrained(identity))

            harness.completePreviewCancellation()
            for _ in 0..<100 where !harness.coordinator.isDevelopmentWorkDrained(identity) {
                await Task.yield()
            }
            XCTAssertTrue(harness.coordinator.isDevelopmentWorkDrained(identity))
        }
    }

    func testExplicitCancelDeletesIncompleteRealSessionDirectory() async throws {
        try await withTemporarySessionsRoot { root in
            let harness = CoordinatorHarness(transcript: "cancelled", sessionsDirectory: root)

            await harness.coordinator.handle(.toggleRecording)
            let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
            let sessionDirectory = root.appendingPathComponent(sessionID.rawValue.uuidString, isDirectory: true)
            let audioURL = sessionDirectory.appendingPathComponent("audio.wav")
            try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
            try Data("discard me".utf8).write(to: audioURL)

            await harness.coordinator.handle(.cancelRecording)

            XCTAssertFalse(FileManager.default.fileExists(atPath: sessionDirectory.path))
            XCTAssertEqual(harness.cancelledSessionIDs, [sessionID])
        }
    }

    func testCancelAfterStopBeforeFinishedAudioPreservesRealSessionDirectory() async throws {
        try await withTemporarySessionsRoot { root in
            let harness = CoordinatorHarness(transcript: "stopped", sessionsDirectory: root)

            await harness.coordinator.handle(.toggleRecording)
            let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
            let sessionDirectory = root.appendingPathComponent(sessionID.rawValue.uuidString, isDirectory: true)
            let audioURL = sessionDirectory.appendingPathComponent("audio.wav")
            try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
            try Data("stopped audio".utf8).write(to: audioURL)

            await harness.coordinator.handle(.toggleRecording)
            await harness.coordinator.handle(.cancelRecording)

            XCTAssertEqual(try Data(contentsOf: audioURL), Data("stopped audio".utf8))
            XCTAssertTrue(FileManager.default.fileExists(atPath: sessionDirectory.path))
            XCTAssertEqual(harness.stopCount, 1)
            XCTAssertEqual(harness.cancelCount, 0)
            XCTAssertTrue(harness.cancelledSessionIDs.isEmpty)
        }
    }

    func testCancelAfterLimitFinishedAudioPreservesDirectoryAndFinalizes() async throws {
        try await withTemporarySessionsRoot { root in
            let harness = CoordinatorHarness(
                transcript: "limit final",
                suspendsTranscription: true,
                sessionsDirectory: root
            )

            await harness.coordinator.handle(.toggleRecording)
            let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
            let sessionDirectory = root.appendingPathComponent(sessionID.rawValue.uuidString, isDirectory: true)
            let audioURL = sessionDirectory.appendingPathComponent("audio.wav")
            try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
            try Data("limit audio".utf8).write(to: audioURL)

            await harness.finishRecording()
            await harness.waitUntilTranscriptionStarts()
            await harness.coordinator.handle(.cancelRecording)
            harness.completeTranscription()
            await harness.waitForDelivery()

            XCTAssertEqual(try Data(contentsOf: audioURL), Data("limit audio".utf8))
            XCTAssertEqual(harness.cancelCount, 0)
            XCTAssertTrue(harness.cancelledSessionIDs.isEmpty)
            XCTAssertEqual(harness.savedRecords.single?.outcome, .success)
            XCTAssertEqual(harness.copyCount, 1)
        }
    }

    func testCancelDuringFinishedCallbackHandoffPreservesAudioAndFinalizes() async throws {
        try await withTemporarySessionsRoot { root in
            let harness = CoordinatorHarness(
                transcript: "handoff final",
                suspendsTranscription: true,
                sessionsDirectory: root
            )

            await harness.coordinator.handle(.toggleRecording)
            let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
            let sessionDirectory = root.appendingPathComponent(sessionID.rawValue.uuidString, isDirectory: true)
            let audioURL = sessionDirectory.appendingPathComponent("audio.wav")
            try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
            try Data("handoff audio".utf8).write(to: audioURL)

            harness.handoffFinishedRecordingWithoutYield()
            await harness.coordinator.handle(.cancelRecording)
            await harness.waitUntilTranscriptionStarts()
            guard harness.events.filter({ $0 == .transcribed }).count == 1 else { return }
            harness.completeTranscription()
            await harness.waitForDelivery()

            XCTAssertEqual(try Data(contentsOf: audioURL), Data("handoff audio".utf8))
            XCTAssertEqual(harness.cancelCount, 0)
            XCTAssertTrue(harness.cancelledSessionIDs.isEmpty)
            XCTAssertEqual(harness.savedRecords.single?.outcome, .success)
            XCTAssertEqual(harness.copyCount, 1)
        }
    }

    func testShutdownDuringFinishedCallbackHandoffPreservesAudio() async throws {
        try await withTemporarySessionsRoot { root in
            let harness = CoordinatorHarness(transcript: "shutdown handoff", sessionsDirectory: root)

            await harness.coordinator.handle(.toggleRecording)
            let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
            let sessionDirectory = root.appendingPathComponent(sessionID.rawValue.uuidString, isDirectory: true)
            let audioURL = sessionDirectory.appendingPathComponent("audio.wav")
            try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
            try Data("shutdown handoff audio".utf8).write(to: audioURL)

            harness.handoffFinishedRecordingWithoutYield()
            harness.coordinator.shutdown()
            for _ in 0..<100 { await Task.yield() }

            XCTAssertEqual(try Data(contentsOf: audioURL), Data("shutdown handoff audio".utf8))
            XCTAssertEqual(harness.cancelCount, 0)
            XCTAssertTrue(harness.cancelledSessionIDs.isEmpty)
            XCTAssertEqual(harness.coordinator.snapshot.status, .idle)
        }
    }

    func testDevelopmentCleanupDuringFinishedCallbackHandoffDrainsWithoutDeletingAudio() async throws {
        try await withTemporarySessionsRoot { root in
            let harness = CoordinatorHarness(transcript: "development handoff", sessionsDirectory: root)

            let identity = try XCTUnwrap(harness.coordinator.startRecordingForDevelopment())
            let sessionDirectory = root.appendingPathComponent(identity.sessionID.rawValue.uuidString, isDirectory: true)
            let audioURL = sessionDirectory.appendingPathComponent("audio.wav")
            try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
            try Data("development handoff audio".utf8).write(to: audioURL)

            harness.handoffFinishedRecordingWithoutYield()
            XCTAssertTrue(harness.coordinator.cancelDevelopmentWork(identity))
            for _ in 0..<100 where !harness.coordinator.isDevelopmentWorkDrained(identity) {
                await Task.yield()
            }

            XCTAssertTrue(harness.coordinator.isDevelopmentWorkDrained(identity))
            XCTAssertEqual(try Data(contentsOf: audioURL), Data("development handoff audio".utf8))
            XCTAssertEqual(harness.cancelCount, 0)
            XCTAssertTrue(harness.cancelledSessionIDs.isEmpty)
            XCTAssertEqual(harness.coordinator.snapshot.status, .cancelled)
        }
    }

    func testFourSequentialStopPendingDevelopmentCleanupsLeaveNoRecordingState() async throws {
        try await withTemporarySessionsRoot { root in
            let harness = CoordinatorHarness(transcript: "stopped cleanup", sessionsDirectory: root)

            for cycle in 0..<4 {
                let identity = try XCTUnwrap(harness.coordinator.startRecordingForDevelopment())
                let sessionDirectory = root.appendingPathComponent(identity.sessionID.rawValue.uuidString, isDirectory: true)
                let audioURL = sessionDirectory.appendingPathComponent("audio.wav")
                try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
                try Data("stopped \(cycle)".utf8).write(to: audioURL)

                harness.coordinator.stopRecording(sessionID: identity.sessionID)
                XCTAssertTrue(harness.coordinator.cancelDevelopmentWork(identity))
                for _ in 0..<100 where !harness.coordinator.isDevelopmentWorkDrained(identity) {
                    await Task.yield()
                }

                XCTAssertTrue(harness.coordinator.isDevelopmentWorkDrained(identity))
                XCTAssertEqual(harness.coordinator.snapshot.status, .cancelled)
                XCTAssertEqual(try Data(contentsOf: audioURL), Data("stopped \(cycle)".utf8))
            }

            XCTAssertEqual(harness.startedSessionIDs.count, 4)
            XCTAssertEqual(harness.cancelCount, 0)
        }
    }

    func testFourSequentialTranscribingDevelopmentCleanupsPreserveAudioAndCapacity() async throws {
        try await withTemporarySessionsRoot { root in
            let harness = CoordinatorHarness(
                transcript: "stopped processing",
                suspendsTranscription: true,
                sessionsDirectory: root
            )

            for cycle in 0..<4 {
                let identity = try XCTUnwrap(harness.coordinator.startRecordingForDevelopment())
                let sessionDirectory = root.appendingPathComponent(identity.sessionID.rawValue.uuidString, isDirectory: true)
                let audioURL = sessionDirectory.appendingPathComponent("audio.wav")
                try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
                try Data("processing \(cycle)".utf8).write(to: audioURL)

                harness.coordinator.stopRecording(sessionID: identity.sessionID)
                await harness.finishRecording(at: cycle)
                await harness.waitUntilTranscriptionStarts(count: cycle + 1)
                XCTAssertTrue(harness.coordinator.cancelDevelopmentWork(identity))
                harness.completeTranscription(at: cycle)
                for _ in 0..<100 where !harness.coordinator.isDevelopmentWorkDrained(identity) {
                    await Task.yield()
                }

                XCTAssertTrue(harness.coordinator.isDevelopmentWorkDrained(identity))
                XCTAssertEqual(harness.coordinator.snapshot.status, .cancelled)
                XCTAssertEqual(try Data(contentsOf: audioURL), Data("processing \(cycle)".utf8))
            }

            XCTAssertEqual(harness.startedSessionIDs.count, 4)
            XCTAssertEqual(harness.cancelCount, 0)
            XCTAssertTrue(harness.savedRecords.isEmpty)
            XCTAssertEqual(harness.copyCount, 0)
        }
    }

    func testDevelopmentCleanupCancelsDeliveredHistoryWithoutDeletingRecord() async throws {
        try await withTemporarySessionsRoot { root in
            let harness = CoordinatorHarness(
                transcript: "durable debug cleanup",
                organizationSettings: remoteOrganizationSettings(),
                suspendsHistorySuggestions: true,
                sessionsDirectory: root
            )

            await harness.coordinator.handle(.toggleRecording)
            await harness.coordinator.handle(.toggleRecording)
            await harness.finishRecording()
            await harness.waitForDelivery()
            await harness.waitUntilHistorySuggestionsStarts()
            let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
            let identity = try XCTUnwrap(harness.coordinator.developmentWorkIdentity(sessionID: sessionID))

            XCTAssertTrue(harness.coordinator.cancelDevelopmentWork(identity))
            harness.completeHistorySuggestions()
            for _ in 0..<100 where !harness.coordinator.isDevelopmentWorkDrained(identity) {
                await Task.yield()
            }

            XCTAssertTrue(harness.coordinator.isDevelopmentWorkDrained(identity))
            XCTAssertEqual(try harness.store?.load(id: sessionID).id, sessionID)
            XCTAssertTrue(harness.organizationInputs.isEmpty)
            XCTAssertEqual(harness.providerStarts, 0)
        }
    }

    func testControllerStopCancelsRunningAndQueuedOrganizationLaneTasks() async throws {
        let (harness, sessionID, selectedID) = try await makeBlockedSelectedHistoryHarness()
        let controller = AppController(state: AppState(), coordinator: harness.coordinator)
        let barrier = IntentBarrier()
        let recordingStartsBeforeStop = harness.startedSessionIDs.count
        let copiesBeforeStop = harness.copyCount
        var queuedActionRan = false

        controller.enqueueOrganizationBarrierForDevelopment { await barrier.wait() }
        await barrier.waitUntilEntered()
        controller.enqueueOrganizationBarrierForDevelopment {
            queuedActionRan = true
            await harness.coordinator.handle(
                .enrichLinks(sessionID: sessionID, selectedRecordIDs: [selectedID])
            )
        }

        controller.stop()
        await barrier.release()

        let cancellationObserved = await barrier.waitUntilFinished()
        XCTAssertTrue(cancellationObserved)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertFalse(queuedActionRan)
        XCTAssertEqual(harness.startedSessionIDs.count, recordingStartsBeforeStop)
        XCTAssertTrue(harness.organizationInputs.isEmpty)
        XCTAssertEqual(harness.providerStarts, 0)
        XCTAssertEqual(harness.copyCount, copiesBeforeStop)
        XCTAssertNil(harness.coordinator.snapshot.sessionID)
        XCTAssertEqual(harness.coordinator.snapshot.status, .idle)
    }

    func testControllerStopCancelsRunningAndQueuedRecordingLaneTasks() async {
        let harness = CoordinatorHarness(transcript: "late")
        let controller = AppController(
            state: AppState(),
            coordinator: harness.coordinator,
            microphoneAuthorizationStatus: { .authorized }
        )
        let barrier = IntentBarrier()

        controller.enqueueBarrierForDevelopment { await barrier.wait() }
        await barrier.waitUntilEntered()
        controller.startRecordingFromUI()

        controller.stop()
        await barrier.release()

        let cancellationObserved = await barrier.waitUntilFinished()
        XCTAssertTrue(cancellationObserved)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertTrue(harness.startedSessionIDs.isEmpty)
        XCTAssertTrue(harness.organizationInputs.isEmpty)
        XCTAssertEqual(harness.providerStarts, 0)
        XCTAssertEqual(harness.copyCount, 0)
        XCTAssertNil(harness.coordinator.snapshot.sessionID)
        XCTAssertEqual(harness.coordinator.snapshot.status, .idle)
    }

    func testSelectedHistorySuccessAfterShutdownCannotWriteOrEnqueue() async throws {
        let selectedID = SessionID(rawValue: UUID())
        let harness = CoordinatorHarness(
            transcript: "delivered text",
            historySuggestions: HistorySuggestions(
                suggestedSummaries: [HistorySummaryDTO(candidateID: "h1", summary: "related")],
                localRecordByCandidateID: ["h1": selectedID]
            )
        )
        await harness.runOneSession()
        let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
        harness.setOrganizationSettings(remoteOrganizationSettings(allowsHistory: true))
        harness.setSuspendsHistorySuggestions(true)
        Task { @MainActor in
            await harness.coordinator.handle(.enrichLinks(sessionID: sessionID, selectedRecordIDs: [selectedID]))
        }
        await harness.waitUntilHistorySuggestionsStarts()

        harness.coordinator.shutdown()
        let shutdownSnapshot = harness.coordinator.snapshot
        harness.completeHistorySuggestions()
        for _ in 0..<100 { await Task.yield() }

        XCTAssertEqual(harness.coordinator.snapshot, shutdownSnapshot)
        XCTAssertNil(harness.coordinator.snapshot.sessionID)
        XCTAssertNil(harness.coordinator.developmentWorkIdentity(sessionID: sessionID))
        XCTAssertEqual(harness.coordinator.snapshot.status, .idle)
        XCTAssertTrue(harness.organizationInputs.isEmpty)
        XCTAssertEqual(harness.providerStarts, 0)
    }

    func testSelectedHistoryErrorAfterShutdownCannotPublishFailureOrEnqueue() async throws {
        let selectedID = SessionID(rawValue: UUID())
        let harness = CoordinatorHarness(transcript: "delivered text")
        await harness.runOneSession()
        let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
        harness.setOrganizationSettings(remoteOrganizationSettings(allowsHistory: true))
        harness.setSuspendsHistorySuggestions(true)
        Task { @MainActor in
            await harness.coordinator.handle(.enrichLinks(sessionID: sessionID, selectedRecordIDs: [selectedID]))
        }
        await harness.waitUntilHistorySuggestionsStarts()

        harness.coordinator.shutdown()
        let shutdownSnapshot = harness.coordinator.snapshot
        harness.failHistorySuggestions(TestError.disk)
        for _ in 0..<100 { await Task.yield() }

        XCTAssertEqual(harness.coordinator.snapshot, shutdownSnapshot)
        XCTAssertNil(harness.coordinator.snapshot.sessionID)
        XCTAssertNil(harness.coordinator.developmentWorkIdentity(sessionID: sessionID))
        XCTAssertEqual(harness.coordinator.snapshot.status, .idle)
        XCTAssertTrue(harness.organizationInputs.isEmpty)
        XCTAssertEqual(harness.providerStarts, 0)
    }

    func testSelectedHistorySuccessAfterOwningTaskCancellationCannotWriteOrEnqueue() async throws {
        let (harness, sessionID, selectedID) = try await makeBlockedSelectedHistoryHarness()
        let task = Task { @MainActor in
            await harness.coordinator.handle(.enrichLinks(sessionID: sessionID, selectedRecordIDs: [selectedID]))
        }
        await harness.waitUntilHistorySuggestionsStarts()
        let identity = try XCTUnwrap(harness.coordinator.developmentWorkIdentity(sessionID: sessionID))
        let snapshot = harness.coordinator.snapshot

        task.cancel()
        harness.completeHistorySuggestions()
        await task.value

        XCTAssertEqual(harness.coordinator.snapshot, snapshot)
        XCTAssertEqual(harness.coordinator.developmentWorkIdentity(sessionID: sessionID), identity)
        XCTAssertTrue(harness.organizationUpdates.isEmpty)
        XCTAssertTrue(harness.organizationInputs.isEmpty)
        XCTAssertEqual(harness.providerStarts, 0)
        harness.coordinator.shutdown()
    }

    func testSelectedHistoryErrorAfterOwningTaskCancellationCannotPublishFailureOrEnqueue() async throws {
        let (harness, sessionID, selectedID) = try await makeBlockedSelectedHistoryHarness()
        let task = Task { @MainActor in
            await harness.coordinator.handle(.enrichLinks(sessionID: sessionID, selectedRecordIDs: [selectedID]))
        }
        await harness.waitUntilHistorySuggestionsStarts()
        let identity = try XCTUnwrap(harness.coordinator.developmentWorkIdentity(sessionID: sessionID))
        let snapshot = harness.coordinator.snapshot

        task.cancel()
        harness.failHistorySuggestions(TestError.disk)
        await task.value

        XCTAssertEqual(harness.coordinator.snapshot, snapshot)
        XCTAssertEqual(harness.coordinator.developmentWorkIdentity(sessionID: sessionID), identity)
        XCTAssertTrue(harness.organizationUpdates.isEmpty)
        XCTAssertTrue(harness.organizationInputs.isEmpty)
        XCTAssertEqual(harness.providerStarts, 0)
        harness.coordinator.shutdown()
    }

    func testSelectedHistorySuccessForStaleRequestCannotOverwriteOrEnqueue() async throws {
        let (harness, sessionID, selectedID) = try await makeBlockedSelectedHistoryHarness()
        let taskA = Task { @MainActor in
            await harness.coordinator.handle(.enrichLinks(sessionID: sessionID, selectedRecordIDs: [selectedID]))
        }
        await harness.waitUntilHistorySuggestionsStarts()
        let requestA = try XCTUnwrap(
            harness.coordinator.developmentWorkIdentity(sessionID: sessionID)?.organizationRequestID
        )
        let taskB = Task { @MainActor in
            await harness.coordinator.handle(.retry(sessionID: sessionID, requestID: requestA))
        }
        await harness.waitUntilHistorySuggestionsStarts(count: 2)
        let identityB = try XCTUnwrap(harness.coordinator.developmentWorkIdentity(sessionID: sessionID))
        let snapshot = harness.coordinator.snapshot

        harness.completeHistorySuggestions(at: 0)
        await taskA.value

        XCTAssertEqual(harness.coordinator.snapshot, snapshot)
        XCTAssertEqual(harness.coordinator.developmentWorkIdentity(sessionID: sessionID), identityB)
        XCTAssertTrue(harness.organizationUpdates.isEmpty)
        XCTAssertTrue(harness.organizationInputs.isEmpty)
        XCTAssertEqual(harness.providerStarts, 0)

        taskB.cancel()
        harness.coordinator.shutdown()
        harness.completeHistorySuggestions(at: 1)
        await taskB.value
    }

    func testSelectedHistoryErrorForStaleRequestCannotPublishFailureOrEnqueue() async throws {
        let (harness, sessionID, selectedID) = try await makeBlockedSelectedHistoryHarness()
        let taskA = Task { @MainActor in
            await harness.coordinator.handle(.enrichLinks(sessionID: sessionID, selectedRecordIDs: [selectedID]))
        }
        await harness.waitUntilHistorySuggestionsStarts()
        let requestA = try XCTUnwrap(
            harness.coordinator.developmentWorkIdentity(sessionID: sessionID)?.organizationRequestID
        )
        let taskB = Task { @MainActor in
            await harness.coordinator.handle(.retry(sessionID: sessionID, requestID: requestA))
        }
        await harness.waitUntilHistorySuggestionsStarts(count: 2)
        let identityB = try XCTUnwrap(harness.coordinator.developmentWorkIdentity(sessionID: sessionID))
        let snapshot = harness.coordinator.snapshot

        harness.failHistorySuggestions(TestError.disk, at: 0)
        await taskA.value

        XCTAssertEqual(harness.coordinator.snapshot, snapshot)
        XCTAssertEqual(harness.coordinator.developmentWorkIdentity(sessionID: sessionID), identityB)
        XCTAssertTrue(harness.organizationUpdates.isEmpty)
        XCTAssertTrue(harness.organizationInputs.isEmpty)
        XCTAssertEqual(harness.providerStarts, 0)

        taskB.cancel()
        harness.coordinator.shutdown()
        harness.completeHistorySuggestions(at: 1)
        await taskB.value
    }

    func testMenuStopRemainsSessionBoundWhenPermissionIsDenied() async throws {
        let harness = CoordinatorHarness(transcript: "final")
        await harness.coordinator.handle(.toggleRecording)
        let recordingSessionID = try XCTUnwrap(harness.coordinator.snapshot.sessionID)
        let state = AppState()
        state.snapshot = harness.coordinator.snapshot
        var microphoneRequestCount = 0
        let controller = AppController(
            state: state,
            coordinator: harness.coordinator,
            microphoneAuthorizationStatus: { .denied },
            requestMicrophonePermission: { _ in microphoneRequestCount += 1 }
        )

        controller.toggleRecordingFromUI()
        for _ in 0..<100 where harness.stopCount == 0 {
            await Task.yield()
        }

        XCTAssertEqual(harness.stopCount, 1)
        XCTAssertEqual(harness.coordinator.snapshot.sessionID, recordingSessionID)
        XCTAssertEqual(microphoneRequestCount, 0)
        XCTAssertEqual(state.snapshot.status, .recording)
        XCTAssertEqual(state.snapshot.message, "Recording")
    }

    func testMenuStartWithMissingSenseVoiceDoesNotRequestPermissionOrStartRecording() async {
        let harness = CoordinatorHarness(transcript: "final")
        let state = AppState()
        var microphoneRequestCount = 0
        let controller = AppController(
            state: state,
            coordinator: harness.coordinator,
            modelError: "SenseVoice model is unavailable.",
            microphoneAuthorizationStatus: { .notDetermined },
            requestMicrophonePermission: { _ in microphoneRequestCount += 1 }
        )

        controller.startRecordingFromUI()
        await Task.yield()

        XCTAssertEqual(microphoneRequestCount, 0)
        XCTAssertTrue(harness.startedSessionIDs.isEmpty)
        XCTAssertEqual(state.snapshot.status, .failed)
        XCTAssertEqual(state.snapshot.message, "SenseVoice model is unavailable.")
    }

    func testStaleMenuActionsForSessionADoNotStartOrAffectSessionB() async throws {
        let harness = CoordinatorHarness(transcript: "final")
        await harness.coordinator.handle(.toggleRecording)
        let sessionA = try XCTUnwrap(harness.coordinator.snapshot.sessionID)
        let controller = AppController(state: AppState(), coordinator: harness.coordinator)
        let barrier = IntentBarrier()

        controller.enqueueBarrierForDevelopment { await barrier.wait() }
        await barrier.waitUntilEntered()
        controller.stopRecordingFromUI(sessionID: sessionA)
        controller.cancelRecordingFromUI(sessionID: sessionA)

        await harness.coordinator.cancelRecording(sessionID: sessionA)
        await harness.coordinator.handle(.toggleRecording)
        let sessionB = try XCTUnwrap(harness.coordinator.snapshot.sessionID)
        await barrier.release()
        for _ in 0..<100 { await Task.yield() }

        XCTAssertNotEqual(sessionA, sessionB)
        XCTAssertEqual(harness.startedSessionIDs.count, 2)
        XCTAssertEqual(harness.stopCount, 0)
        XCTAssertEqual(harness.cancelledSessionIDs, [sessionA])
        XCTAssertEqual(harness.coordinator.snapshot.sessionID, sessionB)
        XCTAssertEqual(harness.coordinator.snapshot.status, .recording)
    }

    func testStaleMenuStartDoesNotCreateSessionCAfterSessionBStarts() async throws {
        let harness = CoordinatorHarness(transcript: "final")
        let state = AppState()
        let controller = AppController(
            state: state,
            coordinator: harness.coordinator,
            microphoneAuthorizationStatus: { .authorized }
        )
        let barrier = IntentBarrier()

        controller.enqueueBarrierForDevelopment { await barrier.wait() }
        await barrier.waitUntilEntered()
        controller.startRecordingFromUI()

        await harness.coordinator.handle(.toggleRecording)
        let sessionB = try XCTUnwrap(harness.coordinator.snapshot.sessionID)
        state.snapshot = harness.coordinator.snapshot
        await barrier.release()
        for _ in 0..<100 { await Task.yield() }

        XCTAssertEqual(harness.startedSessionIDs.count, 1)
        XCTAssertEqual(harness.coordinator.snapshot.sessionID, sessionB)
        XCTAssertEqual(harness.coordinator.snapshot.status, .recording)
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

    func testControllerRecordingLaneStartsWhileOrganizationHistoryLoadIsBlocked() async throws {
        let selectedID = SessionID(rawValue: UUID())
        let harness = CoordinatorHarness(
            transcript: "first result",
            organizationSettings: remoteOrganizationSettings(allowsHistory: true),
            historySuggestions: HistorySuggestions(
                suggestedSummaries: [HistorySummaryDTO(candidateID: "h1", summary: "related")],
                localRecordByCandidateID: ["h1": selectedID]
            )
        )
        let state = AppState()
        let controller = AppController(
            state: state,
            coordinator: harness.coordinator,
            microphoneAuthorizationStatus: { .authorized }
        )

        await harness.runOneSession()
        await harness.waitUntilOrganizationFinishes()
        let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
        harness.setSuspendsHistorySuggestions(true)
        controller.dispatchOrganizationForDevelopment(
            .enrichLinks(sessionID: sessionID, selectedRecordIDs: [selectedID])
        )
        await harness.waitUntilHistorySuggestionsStarts()

        controller.startRecordingFromUI()
        for _ in 0..<100 where harness.startedSessionIDs.count < 2 {
            await Task.yield()
        }

        XCTAssertEqual(harness.startedSessionIDs.count, 2)
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

    func testSessionBoundCancelCannotCancelANewerRecording() async throws {
        let harness = CoordinatorHarness(transcript: "reviewed")

        await harness.coordinator.handle(.toggleRecording)
        let staleSessionID = try XCTUnwrap(harness.startedSessionIDs.single)
        await harness.coordinator.handle(.cancelRecording)
        await harness.coordinator.handle(.toggleRecording)
        let currentSessionID = try XCTUnwrap(harness.startedSessionIDs.last)

        await harness.coordinator.cancelRecording(sessionID: staleSessionID)

        XCTAssertNotEqual(staleSessionID, currentSessionID)
        XCTAssertEqual(harness.coordinator.snapshot.sessionID, currentSessionID)
        XCTAssertEqual(harness.coordinator.snapshot.status, .recording)
        XCTAssertEqual(harness.cancelledSessionIDs, [staleSessionID])
    }

    func testRecordingElapsedTimeUsesInjectedClockOnAudioLevelPublish() async {
        let clock = TestClock(now: Date(timeIntervalSince1970: 100))
        let harness = CoordinatorHarness(transcript: "clock", now: { clock.now })

        await harness.coordinator.handle(.toggleRecording)
        clock.now = Date(timeIntervalSince1970: 112.345)
        harness.publishAudioLevel(0.5)
        await Task.yield()

        XCTAssertEqual(harness.coordinator.snapshot.elapsedMilliseconds, 12_345)
    }

    func testUnavailablePreviewStillDeliversSenseVoiceFinal() async throws {
        let harness = CoordinatorHarness(transcript: "SenseVoice only", streamingText: "")

        await harness.runOneSession()

        XCTAssertEqual(harness.savedRecords.single?.senseVoiceText, "SenseVoice only")
        XCTAssertNil(harness.savedRecords.single?.streamingText)
        XCTAssertEqual(harness.savedRecords.single?.finalSource, .senseVoice)
        XCTAssertEqual(harness.copiedTexts, ["SenseVoice only"])
    }

    func testUnavailableLivePreviewRemainsVisibleWhileRecordingAndAudioCallbacksAreAccepted() async {
        let harness = CoordinatorHarness(
            transcript: "SenseVoice only",
            livePreviewAvailability: .unavailable
        )

        await harness.coordinator.handle(.toggleRecording)
        harness.publishAudioLevel(0.5)
        await Task.yield()

        XCTAssertEqual(harness.coordinator.snapshot.status, .recording)
        XCTAssertEqual(harness.coordinator.snapshot.livePreviewAvailability, .unavailable)
        XCTAssertEqual(harness.coordinator.snapshot.audioLevel, 0.5)
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

    private func makeBlockedSelectedHistoryHarness() async throws -> (CoordinatorHarness, SessionID, SessionID) {
        let selectedID = SessionID(rawValue: UUID())
        let harness = CoordinatorHarness(
            transcript: "delivered text",
            historySuggestions: HistorySuggestions(
                suggestedSummaries: [HistorySummaryDTO(candidateID: "h1", summary: "related")],
                localRecordByCandidateID: ["h1": selectedID]
            )
        )
        await harness.runOneSession()
        let sessionID = try XCTUnwrap(harness.startedSessionIDs.single)
        harness.setOrganizationSettings(remoteOrganizationSettings(allowsHistory: true))
        harness.setSuspendsHistorySuggestions(true)
        return (harness, sessionID, selectedID)
    }
}

@MainActor
private final class TestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

@MainActor
private final class ManualContinuousClock {
    private(set) var now = ContinuousClock().now

    func advance(by duration: Duration) {
        now += duration
    }
}

private actor ManualDeadlineSleeper {
    private var continuations: [CheckedContinuation<Void, Never>?] = []
    private var durations: [Duration] = []

    func sleep(_ duration: Duration) async throws {
        durations.append(duration)
        await withCheckedContinuation { continuations.append($0) }
    }

    func waitUntilStarted(count: Int = 1) async -> Bool {
        for _ in 0..<100 {
            if continuations.count >= count { return true }
            await Task.yield()
        }
        return false
    }

    func fire(at index: Int = 0) {
        continuations[index]?.resume()
        continuations[index] = nil
    }

    func requestedDurations() -> [Duration] {
        durations
    }
}

private actor IntentBarrier {
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var observedCancellation: Bool?
    private var completionWaiter: CheckedContinuation<Bool, Never>?

    func wait() async {
        entered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
        observedCancellation = Task.isCancelled
        completionWaiter?.resume(returning: Task.isCancelled)
        completionWaiter = nil
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }

    func waitUntilFinished() async -> Bool {
        if let observedCancellation { return observedCancellation }
        return await withCheckedContinuation { completionWaiter = $0 }
    }
}

@MainActor
private func withTemporarySessionsRoot(_ body: (URL) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("SessionCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(root)
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

    struct PolishInput {
        let request: TranscriptPolishRequest
        let localOnly: Bool
        let endpoint: OrganizationEndpointSettings
        let providerKind: ProviderKind
    }

    private let transcript: String
    private let cleanedText: String?
    private let streamingText: String
    private let transcriptionError: Error?
    private let saveError: Error?
    private let saveFailures: Set<Int>
    private let statusWriteError: Error?
    private let cleanupError: Error?
    private let suspendsTranscription: Bool
    private let suspendsPreviewCancellation: Bool
    private let suspendsOrganization: Bool
    private let suspendsPolish: Bool
    private let polishStartClockAdvance: Duration?
    private let polishPreDispatchError: Error?
    private let saveClockAdvances: [Int: Duration]
    private let copyClockAdvance: Duration?
    private let copyResult: Bool
    private let startRecordingErrors: [Error?]
    private var organizationSettings: OrganizationSettings
    private var organizationAPIKey: String
    private let organizationErrors: [Error?]
    private let organizationWriteFailures: Set<Int>
    private let persistedRecords: [TranscriptRecord]
    private let historySuggestions: HistorySuggestions
    private var suspendsHistorySuggestions: Bool
    private let livePreviewPipeline: LivePreviewPipeline?
    private let livePreviewAvailability: LivePreviewAvailability
    private let now: @MainActor () -> Date
    private let continuousClock: ManualContinuousClock
    private let polishDeadlineSleeper = ManualDeadlineSleeper()
    private let sessionsDirectory: URL?
    private var historySuggestionsError: Error?
    private var onFinished: [((RecordedAudio) -> Void)] = []
    private var onFailed: [((RecordedAudio) -> Void)] = []
    private var onPreview: [(@MainActor (SessionID, String) -> Void)] = []
    private var onPreviewUnavailable: [(@MainActor (SessionID) -> Void)] = []
    private var onLevel: [(@Sendable (Float) -> Void)] = []
    private var recorderSessionID: SessionID?
    private var pcmFeeds: [LivePreviewPipeline.Feed] = []
    private var transcriptionContinuations: [CheckedContinuation<TranscriptionResult, Error>?] = []
    private var previewCancellationContinuations: [CheckedContinuation<Void, Never>?] = []
    private var organizationContinuations: [UnsafeContinuation<OrganizationOutput, Never>?] = []
    private var polishContinuations: [CheckedContinuation<TranscriptPolishOutcome, Error>?] = []
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
    private(set) var saveAttemptCount = 0
    private(set) var deliveryStatuses: [DeliveryStatus] = []
    private(set) var deliveryReceipts: [TranscriptDeliveryReceipt] = []
    private(set) var polishInputs: [PolishInput] = []
    private(set) var organizationInputs: [OrganizationInput] = []
    private(set) var organizationSecretLoadCount = 0
    private(set) var organizationWriteAttempts: [(sessionID: SessionID, organization: OrganizationRecord)] = []
    private(set) var organizationUpdates: [(sessionID: SessionID, organization: OrganizationRecord)] = []
    private(set) var activeOrganizationCallCount = 0
    private(set) var providerStarts = 0
    private(set) var maximumOrganizationCallCount = 0
    private(set) var timeline: [String] = []
    private(set) var scheduledSecondaryRemovals: [(delay: TimeInterval, action: @MainActor () -> Void)] = []
    private(set) var store: TranscriptStore?

    private(set) lazy var coordinator = makeCoordinator()

    init(
        transcript: String,
        cleanedText: String? = nil,
        streamingText: String = "",
        transcriptionError: Error? = nil,
        saveError: Error? = nil,
        saveFailures: Set<Int> = [],
        statusWriteError: Error? = nil,
        cleanupError: Error? = nil,
        suspendsTranscription: Bool = false,
        suspendsPreviewCancellation: Bool = false,
        copyResult: Bool = true,
        startRecordingErrors: [Error?] = [],
        organizationSettings: OrganizationSettings = OrganizationSettings(),
        organizationAPIKey: String = "synthetic-key",
        suspendsOrganization: Bool = false,
        suspendsPolish: Bool = false,
        polishStartClockAdvance: Duration? = nil,
        polishPreDispatchError: Error? = nil,
        saveClockAdvances: [Int: Duration] = [:],
        copyClockAdvance: Duration? = nil,
        organizationErrors: [Error?] = [],
        organizationWriteFailures: Set<Int> = [],
        persistedRecords: [TranscriptRecord] = [],
        historySuggestions: HistorySuggestions = HistorySuggestions(suggestedSummaries: [], localRecordByCandidateID: [:]),
        historySuggestionsError: Error? = nil,
        suspendsHistorySuggestions: Bool = false,
        livePreviewPipeline: LivePreviewPipeline? = nil,
        livePreviewAvailability: LivePreviewAvailability = .available,
        now: @escaping @MainActor () -> Date = Date.init,
        continuousClock: ManualContinuousClock = ManualContinuousClock(),
        sessionsDirectory: URL? = nil
    ) {
        self.transcript = transcript
        self.cleanedText = cleanedText
        self.streamingText = streamingText
        self.transcriptionError = transcriptionError
        self.saveError = saveError
        self.saveFailures = saveFailures
        self.statusWriteError = statusWriteError
        self.cleanupError = cleanupError
        self.suspendsTranscription = suspendsTranscription
        self.suspendsPreviewCancellation = suspendsPreviewCancellation
        self.copyResult = copyResult
        self.startRecordingErrors = startRecordingErrors
        self.organizationSettings = organizationSettings
        self.organizationAPIKey = organizationAPIKey
        self.suspendsOrganization = suspendsOrganization
        self.suspendsPolish = suspendsPolish
        self.polishStartClockAdvance = polishStartClockAdvance
        self.polishPreDispatchError = polishPreDispatchError
        self.saveClockAdvances = saveClockAdvances
        self.copyClockAdvance = copyClockAdvance
        self.organizationErrors = organizationErrors
        self.organizationWriteFailures = organizationWriteFailures
        self.persistedRecords = persistedRecords
        self.historySuggestions = historySuggestions
        self.historySuggestionsError = historySuggestionsError
        self.suspendsHistorySuggestions = suspendsHistorySuggestions
        self.livePreviewPipeline = livePreviewPipeline
        self.livePreviewAvailability = livePreviewAvailability
        self.now = now
        self.continuousClock = continuousClock
        self.sessionsDirectory = sessionsDirectory
    }

    private func makeCoordinator() -> SessionCoordinator {
        store = sessionsDirectory.map(TranscriptStore.init(directory:))
        let usesManualPolishDeadline = suspendsPolish
        return SessionCoordinator(
            dependencies: .init(
                startRecording: { [weak self] sessionID, onPreview, onPreviewUnavailable, onLevel, onFinished, onFailed in
                    let attempt = self?.startedSessionIDs.count ?? 0
                    self?.events.append(.recordingStarted)
                    self?.startedSessionIDs.append(sessionID)
                    if attempt < (self?.startRecordingErrors.count ?? 0),
                       let error = self?.startRecordingErrors[attempt] {
                        throw error
                    }
                    self?.recorderSessionID = sessionID
                    self?.onPreview.append(onPreview)
                    self?.onPreviewUnavailable.append(onPreviewUnavailable)
                    self?.onLevel.append(onLevel)
                    self?.onFinished.append(onFinished)
                    self?.onFailed.append(onFailed)
                    if let pipeline = self?.livePreviewPipeline {
                        self?.pcmFeeds.append(pipeline.start(
                            sessionID: sessionID,
                            onPreview: onPreview,
                            onPreviewUnavailable: onPreviewUnavailable
                        ))
                    }
                },
                stopRecording: { [weak self] in
                    self?.stopCount += 1
                    self?.recorderSessionID = nil
                },
                cancelRecording: { [weak self] sessionID in
                    guard let self, recorderSessionID == sessionID else { return false }
                    recorderSessionID = nil
                    if let sessionsDirectory {
                        try? FileManager.default.removeItem(
                            at: sessionsDirectory.appendingPathComponent(sessionID.rawValue.uuidString, isDirectory: true)
                        )
                    }
                    cancelCount += 1
                    cancelledSessionIDs.append(sessionID)
                    audioWasDeleted = true
                    return true
                },
                finishPreview: { [weak self] sessionID in
                    self?.finishedPreviewSessionIDs.append(sessionID)
                    if let pipeline = self?.livePreviewPipeline {
                        return await pipeline.finish(sessionID: sessionID)
                    }
                    return self?.streamingText ?? ""
                },
                cancelPreview: { [weak self] sessionID in
                    guard let self else { return }
                    self.cancelledPreviewSessionIDs.append(sessionID)
                    if self.suspendsPreviewCancellation {
                        await withCheckedContinuation { self.previewCancellationContinuations.append($0) }
                    }
                    await self.livePreviewPipeline?.cancel(sessionID: sessionID)
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
                    let attempt = self.saveAttemptCount
                    self.saveAttemptCount += 1
                    if self.saveFailures.contains(attempt) { throw TestError.disk }
                    try self.store?.save(record)
                    if let duration = self.saveClockAdvances[attempt] {
                        self.continuousClock.advance(by: duration)
                    }
                    self.events.append(.saved)
                    self.timeline.append("saved")
                    self.savedRecords.append(record)
                },
                updateDeliveryStatus: { [weak self] sessionID, status in
                    if let statusWriteError = self?.statusWriteError { throw statusWriteError }
                    try self?.store?.updateDeliveryStatus(id: sessionID, to: status)
                    self?.events.append(.deliveryStatusUpdated)
                    self?.deliveryStatuses.append(status)
                    self?.timeline.append("delivery:\(status.rawValue)")
                },
                updateDelivery: { [weak self] sessionID, status, receipt in
                    if let statusWriteError = self?.statusWriteError { throw statusWriteError }
                    try self?.store?.updateDelivery(id: sessionID, status: status, receipt: receipt)
                    self?.events.append(.deliveryStatusUpdated)
                    self?.deliveryStatuses.append(status)
                    self?.deliveryReceipts.append(receipt)
                    self?.timeline.append("delivery:\(status.rawValue)")
                },
                copy: { [weak self] text in
                    if let duration = self?.copyClockAdvance {
                        self?.continuousClock.advance(by: duration)
                    }
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
                currentTerminology: { [weak self] in
                    self?.organizationSettings.transcriptTerminology ?? []
                },
                polish: { [weak self] request, localOnly, willDispatch in
                    guard let self else { throw TestError.deallocated }
                    if let polishPreDispatchError = self.polishPreDispatchError {
                        throw polishPreDispatchError
                    }
                    let dispatch = try AppController.makePolishDispatchSnapshot(
                        localOnly: localOnly,
                        loadSettings: { self.organizationSettings },
                        loadAPIKey: { _ in self.organizationAPIKey }
                    )
                    let providerKind: ProviderKind = dispatch.endpoint.isLoopback ? .local : .remote
                    willDispatch(dispatch.endpoint, providerKind)
                    self.polishInputs.append(PolishInput(
                        request: request,
                        localOnly: localOnly,
                        endpoint: dispatch.endpoint,
                        providerKind: providerKind
                    ))
                    if let duration = self.polishStartClockAdvance {
                        self.continuousClock.advance(by: duration)
                    }
                    guard self.suspendsPolish else {
                        throw TranscriptPolishDispatchError.notEligible
                    }
                    return try await withCheckedThrowingContinuation { self.polishContinuations.append($0) }
                },
                sleepForPolishDeadline: { [polishDeadlineSleeper] duration in
                    if usesManualPolishDeadline {
                        try await polishDeadlineSleeper.sleep(duration)
                    } else {
                        try await Task.sleep(for: duration)
                    }
                },
                continuousNow: { [continuousClock] in continuousClock.now },
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
                    self.providerStarts += 1
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
            livePreviewAvailability: livePreviewAvailability,
            now: now,
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

    func runUntilPolishStarts() async {
        await coordinator.handle(.toggleRecording)
        await coordinator.handle(.toggleRecording)
        await finishRecording()
        await waitUntilPolishStarts()
        await waitUntilPolishDeadlineStarts()
    }

    func waitUntilPolishDeadlineStarts(expectedDuration: Duration = .milliseconds(1_500)) async {
        let deadlineStarted = await polishDeadlineSleeper.waitUntilStarted()
        let durations = await polishDeadlineSleeper.requestedDurations()
        XCTAssertTrue(deadlineStarted)
        XCTAssertEqual(durations, [expectedDuration])
        XCTAssertEqual(savedRecords.count, 1)
    }

    func finishRecording(at index: Int? = nil) async {
        recorderSessionID = nil
        events.append(.recordingFinished)
        let callback = index.map { onFinished[$0] } ?? onFinished.last
        callback?(RecordedAudio(url: audioURL, durationMilliseconds: 1_000))
        await Task.yield()
    }

    func handoffFinishedRecordingWithoutYield(at index: Int? = nil) {
        recorderSessionID = nil
        events.append(.recordingFinished)
        let callback = index.map { onFinished[$0] } ?? onFinished.last
        callback?(RecordedAudio(url: audioURL, durationMilliseconds: 1_000))
    }

    func publishPreview(_ text: String, at index: Int? = nil) {
        let target = index ?? onPreview.count - 1
        onPreview[target](startedSessionIDs[target], text)
    }

    func disableLivePreview(at index: Int? = nil) {
        let target = index ?? onPreviewUnavailable.count - 1
        onPreviewUnavailable[target](startedSessionIDs[target])
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

    func setSuspendsHistorySuggestions(_ suspended: Bool) {
        suspendsHistorySuggestions = suspended
    }

    func waitUntilHistorySuggestionsStarts(count: Int = 1) async {
        for _ in 0..<100 {
            if historySuggestionsContinuations.count >= count { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for history suggestions")
    }

    func completeHistorySuggestions(at index: Int = 0) {
        historySuggestionsContinuations[index]?.resume(returning: historySuggestions)
        historySuggestionsContinuations[index] = nil
    }

    func failHistorySuggestions(_ error: Error, at index: Int = 0) {
        historySuggestionsContinuations[index]?.resume(throwing: error)
        historySuggestionsContinuations[index] = nil
    }

    func failRecording(at index: Int? = nil) async {
        recorderSessionID = nil
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

    func waitUntilPolishStarts(count: Int = 1) async {
        for _ in 0..<100 {
            if polishInputs.count >= count { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for transcript polish")
    }

    func completePolish(_ outcome: TranscriptPolishOutcome, at index: Int = 0) {
        polishContinuations[index]?.resume(returning: outcome)
        polishContinuations[index] = nil
    }

    func firePolishDeadline(at index: Int = 0) async {
        await polishDeadlineSleeper.fire(at: index)
    }

    func requestedPolishDeadlineDurations() async -> [Duration] {
        await polishDeadlineSleeper.requestedDurations()
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

    func completePreviewCancellation(at index: Int = 0) {
        previewCancellationContinuations[index]?.resume()
        previewCancellationContinuations[index] = nil
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

private func polishSettings() -> OrganizationSettings {
    OrganizationSettings(
        endpoint: try! OrganizationEndpointSettings(
            baseURL: URL(string: "https://example.test/v1/chat/completions")!,
            model: "polish-model"
        ),
        cloudConsentVersion: OrganizationSettings.currentCloudConsentVersion,
        polishEnabled: true,
        polishConsentVersion: OrganizationSettings.currentPolishConsentVersion
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
