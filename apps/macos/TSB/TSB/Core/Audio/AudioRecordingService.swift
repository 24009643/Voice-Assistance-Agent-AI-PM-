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

    private let temporaryDirectory: URL
    private let makeRecorder: RecorderFactory
    private var recorder: AudioRecording?
    private var completion: ((RecordedAudio) -> Void)?

    private(set) var activeURL: URL?

    init(
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        makeRecorder: @escaping RecorderFactory = { url, settings in
            try AVAudioRecorder(url: url, settings: settings)
        }
    ) {
        self.temporaryDirectory = temporaryDirectory
        self.makeRecorder = makeRecorder
    }

    func start(sessionID: SessionID, onFinished: @escaping (RecordedAudio) -> Void) throws {
        guard recorder == nil else {
            throw AudioRecordingServiceError.recordingAlreadyActive
        }

        let directory = temporaryDirectory.appendingPathComponent("TSB", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(sessionID.rawValue.uuidString).appendingPathExtension("wav")
        let recording = try makeRecorder(url, Self.recordingSettings)

        recording.delegate = self
        recording.isMeteringEnabled = true
        recorder = recording
        activeURL = url
        completion = onFinished

        guard recording.record(forDuration: Self.maximumDuration) else {
            clearActiveRecording(deleteFile: true)
            throw AudioRecordingServiceError.failedToStart
        }
    }

    func stop() {
        guard let recording = recorder else { return }
        recording.stop()
        finish(recording: recording, successfully: true)
    }

    func cancel() {
        guard let recording = recorder else { return }
        let url = activeURL

        recorder = nil
        activeURL = nil
        completion = nil
        recording.delegate = nil
        recording.stop()

        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func finishActiveRecording(successfully: Bool) {
        finish(recording: recorder, successfully: successfully)
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        finish(recording: recorder, successfully: flag)
    }

    private func finish(recording: AudioRecording?, successfully: Bool) {
        guard let recording, recorder === recording, let url = activeURL else { return }

        let durationMilliseconds = Int((recording.currentTime * 1_000).rounded())
        let callback = completion
        self.recorder = nil
        activeURL = nil
        completion = nil
        recording.delegate = nil

        guard successfully else {
            try? FileManager.default.removeItem(at: url)
            return
        }

        callback?(RecordedAudio(url: url, durationMilliseconds: durationMilliseconds))
    }

    private func clearActiveRecording(deleteFile: Bool) {
        let recording = recorder
        let url = activeURL
        recorder = nil
        activeURL = nil
        completion = nil
        recording?.delegate = nil

        if deleteFile, let url {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
