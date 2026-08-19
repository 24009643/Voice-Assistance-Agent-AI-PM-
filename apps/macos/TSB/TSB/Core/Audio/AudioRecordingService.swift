import AVFoundation
import Foundation

@MainActor
protocol AudioRecording: AnyObject {
    var delegate: AVAudioRecorderDelegate? { get set }
    var isMeteringEnabled: Bool { get set }
    var currentTime: TimeInterval { get }

    func record(forDuration duration: TimeInterval) -> Bool
    func stop()
}

extension AVAudioRecorder: AudioRecording {}

struct RecordedAudio: Equatable, Sendable {
    let url: URL
    let durationMilliseconds: Int
}

enum AudioRecordingServiceError: Error {
    case recordingAlreadyActive
    case failedToStart
}

@MainActor
final class AudioRecordingService: NSObject, @preconcurrency AVAudioRecorderDelegate {
    typealias RecorderFactory = (URL, [String: Any]) throws -> AudioRecording

    static let maximumDuration: TimeInterval = 600
    static let recordingSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16_000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]

    private let sessionsDirectory: URL
    private let makeRecorder: RecorderFactory
    private var recorder: AudioRecording?
    private var completion: ((RecordedAudio) -> Void)?
    private var durationBeforeStopMilliseconds: Int?
    private var activeSessionID: SessionID?

    private(set) var activeURL: URL?

    init(
        sessionsDirectory: URL = TranscriptStore.defaultDirectory,
        makeRecorder: @escaping RecorderFactory = { url, settings in
            try AVAudioRecorder(url: url, settings: settings)
        }
    ) {
        self.sessionsDirectory = sessionsDirectory.standardizedFileURL
        self.makeRecorder = makeRecorder
    }

    func start(sessionID: SessionID, onFinished: @escaping (RecordedAudio) -> Void) throws {
        guard recorder == nil else {
            throw AudioRecordingServiceError.recordingAlreadyActive
        }

        let directory = sessionDirectoryURL(for: sessionID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("audio.wav")

        do {
            let recording = try makeRecorder(url, Self.recordingSettings)
            recording.delegate = self
            recording.isMeteringEnabled = true
            recorder = recording
            activeURL = url
            activeSessionID = sessionID
            completion = onFinished

            guard recording.record(forDuration: Self.maximumDuration) else {
                clearActiveRecording(deleteBundle: true)
                throw AudioRecordingServiceError.failedToStart
            }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func stop() {
        guard let recording = recorder else { return }
        durationBeforeStopMilliseconds = Int((recording.currentTime * 1_000).rounded())
        recording.stop()
        finish(recording: recording, successfully: true)
    }

    func cancel(sessionID: SessionID) {
        if activeSessionID == sessionID, let recording = recorder {
            recorder = nil
            activeURL = nil
            activeSessionID = nil
            completion = nil
            durationBeforeStopMilliseconds = nil
            recording.delegate = nil
            recording.stop()
        }

        try? FileManager.default.removeItem(at: sessionDirectoryURL(for: sessionID))
    }

    func finishActiveRecording(_ recording: AudioRecording? = nil, successfully: Bool) {
        finish(recording: recording ?? recorder, successfully: successfully)
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        finish(recording: recorder, successfully: flag)
    }

    private func finish(recording: AudioRecording?, successfully: Bool) {
        guard let recording, recorder === recording, let url = activeURL else { return }

        let durationMilliseconds = durationBeforeStopMilliseconds
            ?? Int((recording.currentTime * 1_000).rounded())
        let callback = completion
        self.recorder = nil
        activeURL = nil
        activeSessionID = nil
        completion = nil
        durationBeforeStopMilliseconds = nil
        recording.delegate = nil

        guard successfully else { return }

        callback?(RecordedAudio(url: url, durationMilliseconds: durationMilliseconds))
    }

    private func clearActiveRecording(deleteBundle: Bool) {
        let recording = recorder
        let sessionID = activeSessionID
        recorder = nil
        activeURL = nil
        activeSessionID = nil
        completion = nil
        durationBeforeStopMilliseconds = nil
        recording?.delegate = nil

        if deleteBundle, let sessionID {
            try? FileManager.default.removeItem(at: sessionDirectoryURL(for: sessionID))
        }
    }

    private func sessionDirectoryURL(for sessionID: SessionID) -> URL {
        sessionsDirectory.appendingPathComponent(sessionID.rawValue.uuidString, isDirectory: true)
    }
}
