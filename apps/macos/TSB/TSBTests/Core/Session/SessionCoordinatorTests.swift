import Foundation
import Carbon
import XCTest
@testable import TSB

@MainActor
final class SessionCoordinatorTests: XCTestCase {
    func testSuccessfulStopFollowsTheSingleDeliveryOrder() async throws {
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
        XCTAssertTrue(harness.finalizedSessionIDs.isEmpty)
        XCTAssertEqual(harness.removeAudioCount, 0)
        XCTAssertEqual(harness.coordinator.snapshot.status, .failed)
    }

    func testAudioCleanupFailureAfterSaveDoesNotCopyOrDeliver() async throws {
        let harness = CoordinatorHarness(transcript: "原始文本", finalizeAudioError: TestError.cleanup)

        await harness.runOneSession()

        XCTAssertEqual(harness.savedRecords.count, 1)
        XCTAssertEqual(harness.copyCount, 0)
        XCTAssertTrue(harness.deliveryStatuses.isEmpty)
        XCTAssertEqual(harness.coordinator.snapshot.status, .failed)
    }

    func testSuccessfulSessionFinalizesAudioAfterSave() async throws {
        let harness = CoordinatorHarness(transcript: "原始文本")

        await harness.runOneSession()

        XCTAssertEqual(harness.finalizedSessionIDs, harness.savedRecords.map(\.id))
        XCTAssertEqual(harness.removeAudioCount, 0)
    }

    func testCleanupFailureFallsBackToOriginalAfterSave() async throws {
        let harness = CoordinatorHarness(transcript: "原始文本", cleanupError: TestError.cleanup)

        await harness.runOneSession()

        XCTAssertEqual(harness.savedRecords.single?.localCleanedText, "原始文本")
        XCTAssertEqual(harness.copiedTexts, ["原始文本"])
    }

    func testEmptyTextIsNotSavedOrCopied() async throws {
        let harness = CoordinatorHarness(transcript: "   ")

        await harness.runOneSession()

        XCTAssertTrue(harness.savedRecords.isEmpty)
        XCTAssertEqual(harness.copyCount, 0)
        XCTAssertEqual(harness.finalizedSessionIDs.count, 0)
        XCTAssertEqual(harness.removeAudioCount, 1)
        XCTAssertEqual(harness.coordinator.snapshot.status, .cancelled)
    }

    func testEscapeCancelsAndDeletesAudioWithoutSavingOrCopying() async throws {
        let harness = CoordinatorHarness(transcript: "原始文本")

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.cancelRecording)

        XCTAssertEqual(harness.cancelCount, 1)
        XCTAssertTrue(harness.audioWasDeleted)
        XCTAssertTrue(harness.savedRecords.isEmpty)
        XCTAssertEqual(harness.copyCount, 0)
        XCTAssertEqual(harness.finalizedSessionIDs.count, 0)
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
        XCTAssertEqual(harness.finalizedSessionIDs.count, 0)
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
        XCTAssertTrue(harness.savedRecords.isEmpty)
        XCTAssertEqual(harness.copyCount, 0)
        XCTAssertEqual(harness.finalizedSessionIDs.count, 0)
        XCTAssertEqual(harness.removeAudioCount, 1)
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
    private let saveError: Error?
    private let cleanupError: Error?
    private let finalizeAudioError: Error?
    private let removeAudioError: Error?
    private let suspendsTranscription: Bool
    private var onFinished: ((RecordedAudio) -> Void)?
    private var transcriptionContinuation: CheckedContinuation<TranscriptionResult, Error>?
    private var didStartTranscription = false
    private let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("SessionCoordinatorTests.wav")

    private(set) var events: [Event] = []
    private(set) var stopCount = 0
    private(set) var cancelCount = 0
    private(set) var audioWasDeleted = false
    private(set) var copyCount = 0
    private(set) var copiedTexts: [String] = []
    private(set) var savedRecords: [TranscriptRecord] = []
    private(set) var deliveryStatuses: [DeliveryStatus] = []
    private(set) var finalizedSessionIDs: [SessionID] = []
    private(set) var removeAudioCount = 0

    private(set) lazy var coordinator = makeCoordinator()

    init(
        transcript: String,
        saveError: Error? = nil,
        cleanupError: Error? = nil,
        finalizeAudioError: Error? = nil,
        removeAudioError: Error? = nil,
        suspendsTranscription: Bool = false
    ) {
        self.transcript = transcript
        self.saveError = saveError
        self.cleanupError = cleanupError
        self.finalizeAudioError = finalizeAudioError
        self.removeAudioError = removeAudioError
        self.suspendsTranscription = suspendsTranscription
    }

    private func makeCoordinator() -> SessionCoordinator {
        SessionCoordinator(
            dependencies: .init(
                startRecording: { [weak self] _, onFinished in
                    self?.events.append(.recordingStarted)
                    self?.onFinished = onFinished
                },
                stopRecording: { [weak self] in
                    self?.stopCount += 1
                },
                cancelRecording: { [weak self] in
                    self?.cancelCount += 1
                    self?.audioWasDeleted = true
                },
                transcribe: { [weak self] _ in
                    guard let self else { throw TestError.deallocated }
                    self.events.append(.transcribed)
                    self.didStartTranscription = true
                    if self.suspendsTranscription {
                        return try await withCheckedThrowingContinuation { continuation in
                            self.transcriptionContinuation = continuation
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
                    self.savedRecords.append(record)
                },
                updateDeliveryStatus: { [weak self] _, status in
                    self?.events.append(.deliveryStatusUpdated)
                    self?.deliveryStatuses.append(status)
                },
                copy: { [weak self] text in
                    self?.events.append(.copied)
                    self?.copyCount += 1
                    self?.copiedTexts.append(text)
                    return true
                },
                finalizeAudioAfterSave: { [weak self] _, sessionID in
                    guard let self else { throw TestError.deallocated }
                    if let finalizeAudioError { throw finalizeAudioError }
                    finalizedSessionIDs.append(sessionID)
                    audioWasDeleted = true
                },
                removeAudio: { [weak self] _ in
                    if let error = self?.removeAudioError { throw error }
                    self?.audioWasDeleted = true
                    self?.removeAudioCount += 1
                }
            ),
            onSnapshot: { _ in }
        )
    }

    func runOneSession() async {
        await coordinator.handle(.toggleRecording)
        await coordinator.handle(.toggleRecording)
        await finishRecording()
        if saveError == nil, finalizeAudioError == nil, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await waitForDelivery()
        } else {
            await waitForTerminalState()
        }
    }

    func finishRecording() async {
        events.append(.recordingFinished)
        onFinished?(RecordedAudio(url: audioURL, durationMilliseconds: 1_000))
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

    func waitUntilTranscriptionStarts() async {
        for _ in 0..<100 {
            if didStartTranscription {
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

    func completeTranscription() {
        transcriptionContinuation?.resume(returning: TranscriptionResult(text: transcript, detectedLanguage: "zh", eventTags: [], latencyMilliseconds: 12))
        transcriptionContinuation = nil
    }
}

private enum TestError: Error {
    case disk
    case cleanup
    case deallocated
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
