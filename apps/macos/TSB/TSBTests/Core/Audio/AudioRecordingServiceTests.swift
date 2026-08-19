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

    func testTenMinuteFrameLimitMatchesPublicDuration() {
        XCTAssertEqual(AudioRecordingService.maximumDuration, 600)
        XCTAssertEqual(9_600_000, Int(AudioRecordingService.maximumDuration * 16_000))
    }

    func testCancelRemovesOnlyTheSelectedSessionBundleAndIsIdempotent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioRecordingServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let selected = directory.appendingPathComponent(fixedSessionID.rawValue.uuidString, isDirectory: true)
        let sibling = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try Data([1]).write(to: selected.appendingPathComponent("audio.wav"))
        try Data([2]).write(to: sibling.appendingPathComponent("audio.wav"))
        let service = AudioRecordingService(sessionsDirectory: directory)

        service.cancel(sessionID: fixedSessionID)
        service.cancel(sessionID: fixedSessionID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: selected.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
    }

    func testConverterWritesAndChunksTheSame16kMonoFramesIncludingResidualTail() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioRecordingServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("audio.wav")
        let inputFormat = try XCTUnwrap(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)
        )
        var chunks: [[Float]] = []
        var levels: [Float] = []
        let processor = try PCMStreamProcessor(
            inputFormat: inputFormat,
            outputURL: outputURL,
            chunkFrameCount: 3_200,
            maximumFrameCount: 16_000,
            onPCMChunk: { chunks.append($0) },
            onLevel: { levels.append($0) },
            onTerminal: { _ in }
        )

        try processor.consume(makeSineBuffer(format: inputFormat, frameCount: 10_000))
        let frameCount = try processor.finish()
        let secondFinishFrameCount = try processor.finish()

        let file = try AVAudioFile(forReading: outputURL)
        let written = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        )
        try file.read(into: written)
        let writtenSamples = Array(
            UnsafeBufferPointer(start: try XCTUnwrap(written.floatChannelData?[0]), count: Int(written.frameLength))
        )
        let chunkedSamples = chunks.flatMap { $0 }

        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(file.fileFormat.commonFormat, .pcmFormatInt16)
        XCTAssertEqual(frameCount, Int(file.length))
        XCTAssertEqual(secondFinishFrameCount, frameCount)
        XCTAssertEqual(chunkedSamples.count, frameCount)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].count, 3_200)
        XCTAssertLessThan(chunks[1].count, 3_200)
        XCTAssertEqual(writtenSamples.count, chunkedSamples.count)
        for (writtenSample, chunkedSample) in zip(writtenSamples, chunkedSamples) {
            XCTAssertEqual(writtenSample, chunkedSample, accuracy: 0.000_1)
        }
        XCTAssertFalse(levels.isEmpty)
        XCTAssertTrue(levels.allSatisfy { (0 ... 1).contains($0) })
    }

    func testCaptureLifecycleReleasesResourcesOnceForStopCancelAndLimit() {
        for reason in AudioCaptureLifecycle.EndReason.allCases {
            var lifecycle = AudioCaptureLifecycle()
            var releaseCount = 0

            XCTAssertTrue(lifecycle.end(reason: reason) { releaseCount += 1 })
            XCTAssertFalse(lifecycle.end(reason: reason) { releaseCount += 1 })
            XCTAssertFalse(lifecycle.end(reason: .stop) { releaseCount += 1 })
            XCTAssertEqual(releaseCount, 1)
        }
    }

    func testProcessorStopsAtFrameLimitAndSignalsOnce() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioRecordingServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("audio.wav")
        let format = PCMStreamProcessor.outputFormat
        var chunks: [[Float]] = []
        var terminalSignals: [Bool] = []
        let processor = try PCMStreamProcessor(
            inputFormat: format,
            outputURL: outputURL,
            chunkFrameCount: 320,
            maximumFrameCount: 1_000,
            onPCMChunk: { chunks.append($0) },
            onLevel: { _ in },
            onTerminal: { terminalSignals.append($0) }
        )

        try processor.consume(makeSineBuffer(format: format, frameCount: 2_000))
        try processor.consume(makeSineBuffer(format: format, frameCount: 2_000))
        let frameCount = try processor.finish()

        XCTAssertEqual(frameCount, 1_000)
        XCTAssertEqual(chunks.map(\.count), [320, 320, 320, 40])
        XCTAssertEqual(terminalSignals, [true])
        XCTAssertEqual(try AVAudioFile(forReading: outputURL).length, 1_000)
    }

    private func makeSineBuffer(format: AVAudioFormat, frameCount: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0 ..< Int(format.channelCount) {
            for frame in 0 ..< Int(frameCount) {
                channels[channel][frame] = sin(Float(frame) * 0.02) * 0.25
            }
        }
        return buffer
    }
}
