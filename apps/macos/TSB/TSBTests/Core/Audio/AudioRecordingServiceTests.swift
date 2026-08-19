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

    func testStartUsesTenMinuteLimitAndCancelRemovesActiveWAV() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioRecordingServiceTests-\(UUID().uuidString)", isDirectory: true)
        let fake = FakeAudioRecorder()
        let service = AudioRecordingService(temporaryDirectory: temporaryDirectory) { url, _ in
            FileManager.default.createFile(atPath: url.path, contents: Data())
            fake.url = url
            return fake
        }

        try service.start(sessionID: fixedSessionID, onFinished: { _ in })
        let activeURL = try XCTUnwrap(service.activeURL)

        XCTAssertEqual(fake.recordedDuration, AudioRecordingService.maximumDuration)
        XCTAssertTrue(fake.isMeteringEnabled)

        service.cancel()

        XCTAssertNil(service.activeURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: activeURL.path))
    }

    func testManualStopCapturesDurationBeforeResetAndSynchronousDelegateDeliversOnce() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioRecordingServiceTests-\(UUID().uuidString)", isDirectory: true)
        let fake = FakeAudioRecorder()
        fake.currentTime = 1.25
        let service = AudioRecordingService(temporaryDirectory: temporaryDirectory) { url, _ in
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
    }

    func testFailedFinishDeletesWAVAndDoesNotDeliver() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioRecordingServiceTests-\(UUID().uuidString)", isDirectory: true)
        let fake = FakeAudioRecorder()
        let service = AudioRecordingService(temporaryDirectory: temporaryDirectory) { url, _ in
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: activeURL.path))
    }
}

@MainActor
private final class FakeAudioRecorder: AudioRecording {
    var delegate: AVAudioRecorderDelegate?
    var isMeteringEnabled = false
    var currentTime: TimeInterval = 0
    var recordedDuration: TimeInterval?
    var stopCount = 0
    var url: URL?
    var onStop: (() -> Void)?

    func record(forDuration duration: TimeInterval) -> Bool {
        recordedDuration = duration
        return true
    }

    func stop() {
        stopCount += 1
        currentTime = 0
        onStop?()
    }
}
