@preconcurrency import AVFoundation
import Foundation

struct RecordedAudio: Equatable, Sendable {
    let url: URL
    let durationMilliseconds: Int
}

enum AudioRecordingServiceError: Error {
    case recordingAlreadyActive
    case invalidInputFormat
}

struct AudioCaptureLifecycle {
    enum EndReason: CaseIterable {
        case stop
        case cancel
        case limit
        case failure
    }

    private(set) var endReason: EndReason?

    mutating func end(reason: EndReason, release: () -> Void) -> Bool {
        guard endReason == nil else { return false }
        endReason = reason
        release()
        return true
    }
}

final class PCMStreamProcessor {
    static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private let converter: AVAudioConverter
    private var outputFile: AVAudioFile?
    private let chunkFrameCount: Int
    private let maximumFrameCount: Int
    private let onPCMChunk: ([Float]) -> Void
    private let onLevel: (Float) -> Void
    private let onTerminal: (Bool) -> Void
    private var residual: [Float] = []
    private var didFinish = false
    private var acceptingInput = true
    private(set) var totalOutputFrames = 0

    init(
        inputFormat: AVAudioFormat,
        outputURL: URL,
        chunkFrameCount: Int = 3_200,
        maximumFrameCount: Int = 9_600_000,
        onPCMChunk: @escaping ([Float]) -> Void,
        onLevel: @escaping (Float) -> Void,
        onTerminal: @escaping (Bool) -> Void
    ) throws {
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              chunkFrameCount > 0, maximumFrameCount > 0,
              let converter = AVAudioConverter(from: inputFormat, to: Self.outputFormat) else {
            throw AudioRecordingServiceError.invalidInputFormat
        }
        self.converter = converter
        outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: AudioRecordingService.recordingSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        self.chunkFrameCount = chunkFrameCount
        self.maximumFrameCount = maximumFrameCount
        self.onPCMChunk = onPCMChunk
        self.onLevel = onLevel
        self.onTerminal = onTerminal
        residual.reserveCapacity(chunkFrameCount)
    }

    func consume(_ input: AVAudioPCMBuffer) throws {
        guard acceptingInput, !didFinish else { return }
        try convert(input)
    }

    @discardableResult
    func finish() throws -> Int {
        guard !didFinish else { return totalOutputFrames }
        if acceptingInput { try drainConverter() }
        acceptingInput = false
        didFinish = true
        flushResidual()
        outputFile = nil
        return totalOutputFrames
    }

    @discardableResult
    func cancel() -> Int {
        guard !didFinish else { return totalOutputFrames }
        acceptingInput = false
        didFinish = true
        residual.removeAll(keepingCapacity: false)
        outputFile = nil
        return totalOutputFrames
    }

    private func convert(_ input: AVAudioPCMBuffer) throws {
        let converterInput = ConverterInput(input)
        while acceptingInput {
            let capacity = max(
                1,
                AVAudioFrameCount(ceil(Double(input.frameLength) * 16_000 / input.format.sampleRate) + 32)
            )
            let output = AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: capacity)!
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                guard !converterInput.wasSupplied else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                converterInput.wasSupplied = true
                inputStatus.pointee = .haveData
                return converterInput.buffer
            }
            if let conversionError { throw conversionError }
            try append(output)
            guard status == .haveData else { return }
        }
    }

    private func drainConverter() throws {
        while acceptingInput {
            let output = AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: 4_096)!
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                inputStatus.pointee = .endOfStream
                return nil
            }
            if let conversionError { throw conversionError }
            try append(output)
            if status == .endOfStream || (status != .haveData && output.frameLength == 0) { return }
        }
    }

    private func append(_ buffer: AVAudioPCMBuffer) throws {
        let remaining = maximumFrameCount - totalOutputFrames
        guard remaining > 0, buffer.frameLength > 0,
              let source = buffer.floatChannelData?[0] else { return }
        let count = min(remaining, Int(buffer.frameLength))
        let writable: AVAudioPCMBuffer
        if count == Int(buffer.frameLength) {
            writable = buffer
        } else {
            writable = AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: AVAudioFrameCount(count))!
            writable.frameLength = AVAudioFrameCount(count)
            writable.floatChannelData?[0].update(from: source, count: count)
        }
        try outputFile!.write(from: writable)

        let samples = UnsafeBufferPointer(start: source, count: count)
        residual.append(contentsOf: samples)
        totalOutputFrames += count
        let meanSquare = samples.reduce(0) { $0 + ($1 * $1) } / Float(count)
        onLevel(min(1, sqrt(meanSquare)))
        while residual.count >= chunkFrameCount {
            onPCMChunk(Array(residual.prefix(chunkFrameCount)))
            residual.removeFirst(chunkFrameCount)
        }
        if totalOutputFrames == maximumFrameCount {
            acceptingInput = false
            onTerminal(true)
        }
    }

    private func flushResidual() {
        guard !residual.isEmpty else { return }
        onPCMChunk(residual)
        residual.removeAll(keepingCapacity: false)
    }
}

private final class ConverterInput: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var wasSupplied = false

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

private final class AudioBufferReference: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

private final class NativeAudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "com.zhuohengchi.tsb.audio.capture")
    private let terminal: @Sendable (Bool) -> Void
    private let inputFormat: AVAudioFormat
    private let processor: PCMStreamProcessor
    private var lifecycle = AudioCaptureLifecycle()
    private var configurationObserver: NSObjectProtocol?

    @MainActor
    init(
        outputURL: URL,
        onPCMChunk: @escaping @Sendable ([Float]) -> Void,
        onLevel: @escaping @Sendable (Float) -> Void,
        terminal: @escaping @Sendable (Bool) -> Void
    ) throws {
        self.terminal = terminal
        inputFormat = engine.inputNode.outputFormat(forBus: 0)
        processor = try PCMStreamProcessor(
            inputFormat: inputFormat,
            outputURL: outputURL,
            onPCMChunk: onPCMChunk,
            onLevel: onLevel,
            onTerminal: terminal
        )
    }

    @MainActor
    func start() throws {
        let inputNode = engine.inputNode
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let reference = AudioBufferReference(buffer)
            queue.sync {
                do {
                    try processor.consume(reference.buffer)
                } catch {
                    terminal(false)
                }
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw error
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [terminal] _ in terminal(false) }
    }

    @MainActor
    func end(reason: AudioCaptureLifecycle.EndReason) throws -> Int {
        let didEnd = lifecycle.end(reason: reason) {
            if let configurationObserver {
                NotificationCenter.default.removeObserver(configurationObserver)
                self.configurationObserver = nil
            }
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        guard didEnd else { return processor.totalOutputFrames }
        return try queue.sync {
            if reason == .cancel {
                return processor.cancel()
            }
            return try processor.finish()
        }
    }
}

@MainActor
final class AudioRecordingService {
    static let maximumDuration: TimeInterval = 600
    nonisolated(unsafe) static let recordingSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16_000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]

    private let sessionsDirectory: URL
    private var capture: NativeAudioCapture?
    private var completion: ((RecordedAudio) -> Void)?
    private var activeSessionID: SessionID?
    private var activeToken: UUID?

    private(set) var activeURL: URL?

    init(sessionsDirectory: URL = TranscriptStore.defaultDirectory) {
        self.sessionsDirectory = sessionsDirectory.standardizedFileURL
    }

    func start(
        sessionID: SessionID,
        onPCMChunk: @escaping @Sendable ([Float]) -> Void = { _ in },
        onLevel: @escaping @Sendable (Float) -> Void = { _ in },
        onFinished: @escaping (RecordedAudio) -> Void
    ) throws {
        guard capture == nil else { throw AudioRecordingServiceError.recordingAlreadyActive }
        let directory = sessionDirectoryURL(for: sessionID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("audio.wav")
        let token = UUID()

        do {
            let pendingCapture = try NativeAudioCapture(
                outputURL: url,
                onPCMChunk: onPCMChunk,
                onLevel: onLevel,
                terminal: { [weak self] succeeded in
                    Task { @MainActor [weak self] in
                        self?.finish(
                            token: token,
                            reason: succeeded ? .limit : .failure,
                            successfully: succeeded
                        )
                    }
                }
            )
            capture = pendingCapture
            activeURL = url
            activeSessionID = sessionID
            activeToken = token
            completion = onFinished
            try pendingCapture.start()
        } catch {
            clearActiveCapture()
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func stop() {
        guard let activeToken else { return }
        finish(token: activeToken, reason: .stop, successfully: true)
    }

    func cancel(sessionID: SessionID) {
        if activeSessionID == sessionID, capture != nil {
            finish(token: activeToken, reason: .cancel, successfully: false)
        }
        try? FileManager.default.removeItem(at: sessionDirectoryURL(for: sessionID))
    }

    private func finish(
        token: UUID?,
        reason: AudioCaptureLifecycle.EndReason,
        successfully: Bool
    ) {
        guard token == activeToken, let endingCapture = capture, let url = activeURL else { return }
        let callback = completion
        let frameCount: Int
        do {
            frameCount = try endingCapture.end(reason: reason)
        } catch {
            clearActiveCapture()
            return
        }
        clearActiveCapture()
        guard successfully else { return }
        callback?(RecordedAudio(
            url: url,
            durationMilliseconds: Int((Double(frameCount) / 16_000 * 1_000).rounded())
        ))
    }

    private func clearActiveCapture() {
        capture = nil
        activeURL = nil
        activeSessionID = nil
        activeToken = nil
        completion = nil
    }

    private func sessionDirectoryURL(for sessionID: SessionID) -> URL {
        sessionsDirectory.appendingPathComponent(sessionID.rawValue.uuidString, isDirectory: true)
    }
}
