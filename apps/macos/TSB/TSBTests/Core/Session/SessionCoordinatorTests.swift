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
        XCTAssertEqual(harness.coordinator.snapshot, AppSnapshot(
            status: .delivered,
            elapsedMilliseconds: 1_000,
            previewText: "原始文本",
            message: "已复制 · 按 ⌘V 粘贴"
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
        XCTAssertEqual(harness.coordinator.snapshot.status, .failed)
    }

    func testNoSpeechSavesRetainedOutcomeWithoutCopying() async throws {
        let harness = CoordinatorHarness(transcript: "   ")

        await harness.runOneSession()

        XCTAssertEqual(harness.savedRecords.single?.outcome, .noSpeech)
        XCTAssertEqual(harness.savedRecords.single?.localCleanedText, "")
        XCTAssertEqual(harness.copyCount, 0)
        XCTAssertFalse(harness.audioWasDeleted)
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
            status: .delivered,
            elapsedMilliseconds: 1_000,
            previewText: "原始文本",
            message: "已复制，但未能记录复制状态"
        ))
    }

    func testEscapeCancelsAndDeletesAudioWithoutSavingOrCopying() async throws {
        let harness = CoordinatorHarness(transcript: "原始文本")

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.cancelRecording)

        XCTAssertEqual(harness.cancelCount, 1)
        XCTAssertTrue(harness.audioWasDeleted)
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

    private let transcript: String
    private let transcriptionError: Error?
    private let saveError: Error?
    private let statusWriteError: Error?
    private let cleanupError: Error?
    private let suspendsTranscription: Bool
    private let copyResult: Bool
    private var onFinished: [((RecordedAudio) -> Void)] = []
    private var transcriptionContinuations: [CheckedContinuation<TranscriptionResult, Error>?] = []
    private let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("SessionCoordinatorTests.wav")

    private(set) var events: [Event] = []
    private(set) var stopCount = 0
    private(set) var cancelCount = 0
    private(set) var startedSessionIDs: [SessionID] = []
    private(set) var cancelledSessionIDs: [SessionID] = []
    private(set) var audioWasDeleted = false
    private(set) var copyCount = 0
    private(set) var copiedTexts: [String] = []
    private(set) var savedRecords: [TranscriptRecord] = []
    private(set) var deliveryStatuses: [DeliveryStatus] = []
    private(set) var timeline: [String] = []

    private(set) lazy var coordinator = makeCoordinator()

    init(
        transcript: String,
        transcriptionError: Error? = nil,
        saveError: Error? = nil,
        statusWriteError: Error? = nil,
        cleanupError: Error? = nil,
        suspendsTranscription: Bool = false,
        copyResult: Bool = true
    ) {
        self.transcript = transcript
        self.transcriptionError = transcriptionError
        self.saveError = saveError
        self.statusWriteError = statusWriteError
        self.cleanupError = cleanupError
        self.suspendsTranscription = suspendsTranscription
        self.copyResult = copyResult
    }

    private func makeCoordinator() -> SessionCoordinator {
        SessionCoordinator(
            dependencies: .init(
                startRecording: { [weak self] sessionID, onFinished in
                    self?.events.append(.recordingStarted)
                    self?.startedSessionIDs.append(sessionID)
                    self?.onFinished.append(onFinished)
                },
                stopRecording: { [weak self] in
                    self?.stopCount += 1
                },
                cancelRecording: { [weak self] sessionID in
                    self?.cancelCount += 1
                    self?.cancelledSessionIDs.append(sessionID)
                    self?.audioWasDeleted = true
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
                    return CleanResult(text: source.trimmingCharacters(in: .whitespacesAndNewlines), edits: [])
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
                },
                copy: { [weak self] text in
                    self?.events.append(.copied)
                    self?.copyCount += 1
                    self?.copiedTexts.append(text)
                    return self?.copyResult ?? false
                },
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

    func waitForDelivery() async {
        for _ in 0..<100 {
            if !deliveryStatuses.isEmpty {
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
    case deallocated
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
