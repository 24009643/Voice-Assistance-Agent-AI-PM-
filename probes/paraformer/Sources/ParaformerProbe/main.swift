import AVFoundation
import Dispatch
import Foundation

private enum ProbeError: Error, CustomStringConvertible {
    case usage(String)
    case unsupportedAudio(String)

    var description: String {
        switch self {
        case let .usage(message), let .unsupportedAudio(message): message
        }
    }
}

private struct Options {
    let modelDirectory: URL
    let wav: URL
}

private struct ResultLine: Encodable {
    let kind = "result"
    let phase: String
    let text: String
    let elapsedMilliseconds: Int
}

private struct TimingLine: Encodable {
    let kind = "timing"
    let phase: String
    let elapsedMilliseconds: Int
    let audioSeconds: Double
}

private let helpText = """
Usage: ParaformerProbe --model-dir <dir> --wav <16k-mono.wav>

Runs the local online Paraformer recognizer in 200 ms PCM chunks and writes
JSONL timing and recognition-result events to stdout.
"""

private func run(arguments: [String]) async throws {
    if arguments.contains("--help") || arguments.contains("-h") {
        print(helpText)
        return
    }

    let options = try parse(arguments: arguments)
    let bundle = try ModelBundle.validate(at: options.modelDirectory)
    let recognizer = OnlineParaformerRecognizer(modelBundle: bundle)
    let audio = try AVAudioFile(forReading: options.wav)
    let format = audio.processingFormat
    guard Int(format.sampleRate.rounded()) == OnlineParaformerRecognizer.sampleRate,
          format.channelCount == 1,
          format.commonFormat == .pcmFormatFloat32 else {
        throw ProbeError.unsupportedAudio("WAV must decode as 16 kHz mono Float32 PCM: \(options.wav.path)")
    }
    guard let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(OnlineParaformerRecognizer.finalPaddingSamples)
    ) else {
        throw ProbeError.unsupportedAudio("could not allocate PCM buffer")
    }

    var framesRead = 0
    while true {
        buffer.frameLength = 0
        try audio.read(into: buffer, frameCount: buffer.frameCapacity)
        let count = Int(buffer.frameLength)
        guard count > 0 else { break }
        guard let channel = buffer.floatChannelData?[0] else {
            throw ProbeError.unsupportedAudio("WAV has no Float32 PCM channel: \(options.wav.path)")
        }

        let samples = Array(UnsafeBufferPointer(start: channel, count: count))
        let start = ContinuousClock.now
        let events = await recognizer.accept(samples: samples)
        framesRead += count
        let elapsed = milliseconds(from: start, to: .now)
        try writeJSONLine(TimingLine(
            phase: "chunk",
            elapsedMilliseconds: elapsed,
            audioSeconds: Double(framesRead) / Double(OnlineParaformerRecognizer.sampleRate)
        ))
        try write(events: events, elapsedMilliseconds: elapsed)
    }

    let finishStart = ContinuousClock.now
    let events = await recognizer.finish()
    let elapsed = milliseconds(from: finishStart, to: .now)
    try writeJSONLine(TimingLine(
        phase: "finish",
        elapsedMilliseconds: elapsed,
        audioSeconds: Double(framesRead) / Double(OnlineParaformerRecognizer.sampleRate)
    ))
    try write(events: events, elapsedMilliseconds: elapsed)
}

private func parse(arguments: [String]) throws -> Options {
    var modelDirectory: URL?
    var wav: URL?
    var index = 0
    while index < arguments.count {
        guard index + 1 < arguments.count else {
            throw ProbeError.usage("missing value for \(arguments[index])")
        }
        let value = arguments[index + 1]
        switch arguments[index] {
        case "--model-dir": modelDirectory = URL(fileURLWithPath: value)
        case "--wav": wav = URL(fileURLWithPath: value)
        default: throw ProbeError.usage("unknown argument: \(arguments[index])")
        }
        index += 2
    }
    guard let modelDirectory, let wav else { throw ProbeError.usage(helpText) }
    return Options(modelDirectory: modelDirectory, wav: wav)
}

private func write(events: [OnlineRecognizerEvent], elapsedMilliseconds: Int) throws {
    for event in events {
        let line: ResultLine
        switch event {
        case let .partial(text): line = ResultLine(phase: "partial", text: text, elapsedMilliseconds: elapsedMilliseconds)
        case let .final(text): line = ResultLine(phase: "final", text: text, elapsedMilliseconds: elapsedMilliseconds)
        }
        try writeJSONLine(line)
    }
}

private func writeJSONLine<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
}

private func milliseconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Int {
    let duration = start.duration(to: end).components
    return Int(duration.seconds * 1_000 + duration.attoseconds / 1_000_000_000_000_000)
}

Task {
    do {
        try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        exit(0)
    } catch {
        fputs("\(error)\n", stderr)
        exit(1)
    }
}
dispatchMain()
