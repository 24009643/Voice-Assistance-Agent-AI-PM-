import AVFoundation
import XCTest
@testable import TSB

@MainActor
final class AudioRecordingServiceTests: XCTestCase {
    private let fixedSessionID = SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)

    func testRecordingSettingsAre16kMonoLinearPCM() {
        let settings = AudioRecordingService.recordingSettings

        XCTAssertEqual(settings[AVSampleRateKey] as? Double, 16_000)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 1)
        XCTAssertEqual(settings[AVFormatIDKey] as? UInt32, kAudioFormatLinearPCM)
    }

    func testStartUsesTenMinuteLimitAndCancelRemovesOnlyItsSessionBundle() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioRecordingServiceTests-\(UUID().uuidString)", isDirectory: true)
        let fake = FakeAudioRecorder()
        let service = AudioRecordingService(sessionsDirectory: temporaryDirectory) { url, _ in
            FileManager.default.createFile(atPath: url.path, contents: Data())
            fake.url = url
            return fake
        }

        try service.start(sessionID: fixedSessionID, onFinished: { _ in })
        let activeURL = try XCTUnwrap(service.activeURL)
        let expectedURL = temporaryDirectory
            .appendingPathComponent(fixedSessionID.rawValue.uuidString, isDirectory: true)
            .appendingPathComponent("audio.wav")
        let siblingURL = temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("audio.wav")
        try FileManager.default.createDirectory(at: siblingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x01]).write(to: siblingURL)

        XCTAssertEqual(fake.recordedDuration, AudioRecordingService.maximumDuration)
        XCTAssertTrue(fake.isMeteringEnabled)
        XCTAssertEqual(activeURL, expectedURL)

        service.cancel(sessionID: fixedSessionID)

        XCTAssertNil(service.activeURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: activeURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: activeURL.deletingLastPathComponent().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: siblingURL.path))
    }

    func testManualStopCapturesDurationBeforeResetAndSynchronousDelegateDeliversOnce() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioRecordingServiceTests-\(UUID().uuidString)", isDirectory: true)
        let fake = FakeAudioRecorder()
        fake.currentTime = 1.25
        let service = AudioRecordingService(sessionsDirectory: temporaryDirectory) { url, _ in
            FileManager.default.createFile(atPath: url.path, contents: Data())
            fake.url = url
            return fake
        }
        var results: [RecordedAudio] = []

        try service.start(sessionID: fixedSessionID) { recorded in
            results.append(recorded)
        }
        fake.onStop = {
            service.finishActiveRecording(successfully: true)
        }
        service.stop()
        service.finishActiveRecording(successfully: true)

        XCTAssertEqual(results, [RecordedAudio(url: try XCTUnwrap(fake.url), durationMilliseconds: 1_250)])
        XCTAssertNil(service.activeURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(fake.url).path))
    }

    func testFailedFinishRetainsWAVAndDoesNotDeliver() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioRecordingServiceTests-\(UUID().uuidString)", isDirectory: true)
        let fake = FakeAudioRecorder()
        let service = AudioRecordingService(sessionsDirectory: temporaryDirectory) { url, _ in
            FileManager.default.createFile(atPath: url.path, contents: Data())
            fake.url = url
            return fake
        }
        var results: [RecordedAudio] = []

        try service.start(sessionID: fixedSessionID) { results.append($0) }
        let activeURL = try XCTUnwrap(service.activeURL)
        service.finishActiveRecording(successfully: false)

        XCTAssertTrue(results.isEmpty)
        XCTAssertNil(service.activeURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: activeURL.path))
    }

    func testLateCancellationOfCompletedSessionDoesNotDeleteNewerBundle() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioRecordingServiceTests-\(UUID().uuidString)", isDirectory: true)
        let firstID = fixedSessionID
        let secondID = SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)
        let first = FakeAudioRecorder()
        let second = FakeAudioRecorder()
        var recorders = [first, second]
        let service = AudioRecordingService(sessionsDirectory: directory) { url, _ in
            FileManager.default.createFile(atPath: url.path, contents: Data())
            let recorder = recorders.removeFirst()
            recorder.url = url
            return recorder
        }

        try service.start(sessionID: firstID, onFinished: { _ in })
        service.stop()
        try service.start(sessionID: secondID, onFinished: { _ in })
        let secondURL = try XCTUnwrap(service.activeURL)

        service.cancel(sessionID: firstID)
        service.cancel(sessionID: firstID)

        XCTAssertEqual(service.activeURL, secondURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(firstID.rawValue.uuidString).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
    }

    func testLateFinishFromPreviousRecorderDoesNotClearNewerBundle() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioRecordingServiceTests-\(UUID().uuidString)", isDirectory: true)
        let first = FakeAudioRecorder()
        let second = FakeAudioRecorder()
        var recorders = [first, second]
        let service = AudioRecordingService(sessionsDirectory: directory) { url, _ in
            FileManager.default.createFile(atPath: url.path, contents: Data())
            let recorder = recorders.removeFirst()
            recorder.url = url
            return recorder
        }

        try service.start(sessionID: fixedSessionID, onFinished: { _ in })
        service.stop()
        try service.start(sessionID: SessionID(rawValue: UUID()), onFinished: { _ in })
        let secondURL = try XCTUnwrap(service.activeURL)

        service.finishActiveRecording(first, successfully: false)

        XCTAssertEqual(service.activeURL, secondURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
    }

    func testFailedStartRemovesEmptySessionBundle() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioRecordingServiceTests-\(UUID().uuidString)", isDirectory: true)
        let fake = FakeAudioRecorder()
        fake.recordSucceeds = false
        let service = AudioRecordingService(sessionsDirectory: directory) { url, _ in
            FileManager.default.createFile(atPath: url.path, contents: Data())
            return fake
        }

        XCTAssertThrowsError(try service.start(sessionID: fixedSessionID, onFinished: { _ in }))

        XCTAssertNil(service.activeURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(fixedSessionID.rawValue.uuidString).path))
    }
}

@MainActor
private final class FakeAudioRecorder: AudioRecording {
    var delegate: AVAudioRecorderDelegate?
    var isMeteringEnabled = false
    var currentTime: TimeInterval = 0
    var recordSucceeds = true
    var recordedDuration: TimeInterval?
    var stopCount = 0
    var url: URL?
    var onStop: (() -> Void)?

    func record(forDuration duration: TimeInterval) -> Bool {
        recordedDuration = duration
        return recordSucceeds
    }

    func stop() {
        stopCount += 1
        currentTime = 0
        onStop?()
    }
}
