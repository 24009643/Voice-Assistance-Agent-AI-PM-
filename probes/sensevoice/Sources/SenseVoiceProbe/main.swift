import AVFoundation
import Darwin
import Foundation
import SherpaOnnx

enum ProbeError: Error, CustomStringConvertible {
    case usage(String)
    case missingModelFile(String)
    case unsupportedAudio(String)

    var description: String {
        switch self {
        case let .usage(message):
            return message
        case let .missingModelFile(path):
            return "missing model file: \(path)"
        case let .unsupportedAudio(message):
            return message
        }
    }
}

func run(arguments: [String]) throws -> Int {
    if arguments.contains("--help") || arguments.contains("-h") {
        FileHandle.standardOutput.write(Data((helpText + "\n").utf8))
        return 0
    }

    let options = try parse(arguments: arguments)
    let modelFile = options.modelDirectory.appendingPathComponent("model.int8.onnx").path
    let tokensFile = options.modelDirectory.appendingPathComponent("tokens.txt").path
    try requireFile(modelFile)
    try requireFile(tokensFile)

    let manifest = try ModelManifest.load(from: options.manifest)
    let totalStart = ContinuousClock.now
    let baselineRSS = currentResidentSetSize()
    let loadStart = ContinuousClock.now
    let recognizer = makeRecognizer(model: modelFile, tokens: tokensFile)
    let coldLoad = milliseconds(from: loadStart, to: ContinuousClock.now)

    for sample in manifest.samples {
        let audio = try loadMono16kWav(URL(fileURLWithPath: sample.path))
        let decodeStart = ContinuousClock.now
        let chunks = chunkedSamples(audio.samples, maximumFrameCount: audio.sampleRate * 30)
        var transcripts: [String] = []
        var languages: [String] = []
        var events: [String] = []
        var emotions: [String] = []
        for chunk in chunks {
            let decoded = autoreleasepool { () -> (String, String, String, String) in
                let result = recognizer.decode(samples: chunk, sampleRate: audio.sampleRate)
                return (result.text, result.lang, result.event, result.emotion)
            }
            if !decoded.0.isEmpty { transcripts.append(decoded.0) }
            if !decoded.1.isEmpty { languages.append(decoded.1) }
            events.append(contentsOf: splitEvents(decoded.2))
            if !decoded.3.isEmpty { emotions.append(decoded.3) }
        }
        let elapsed = milliseconds(from: decodeStart, to: ContinuousClock.now)
        let output = SampleResult(
            id: sample.id,
            expectedLanguage: sample.language,
            detectedLanguage: languages.first,
            transcript: transcripts.joined(separator: "\n"),
            events: Array(Set(events)).sorted(),
            emotion: emotions.first,
            latencyMilliseconds: elapsed,
            audioDurationSeconds: audio.durationSeconds,
            chunkCount: chunks.count
        )
        try writeJSONLine(output)
    }

    let peakRSS = peakResidentSetSize()
    let metrics = ProcessMetrics(
        sampleCount: manifest.samples.count,
        coldLoadMilliseconds: coldLoad,
        totalElapsedMilliseconds: milliseconds(from: totalStart, to: ContinuousClock.now),
        baselineRSSBytes: baselineRSS,
        peakRSSBytes: peakRSS,
        activePeakRSSDeltaBytes: activePeakDelta(baselineRSSBytes: baselineRSS, peakRSSBytes: peakRSS)
    )
    try writeJSONLine(metrics)
    _ = recognizer
    return 0
}

private struct Options {
    let modelDirectory: URL
    let manifest: URL
}

private let helpText = """
Usage: SenseVoiceProbe --model-dir <dir> --manifest <manifest.jsonl>

Runs a local sherpa-onnx SenseVoice benchmark. The manifest must be JSONL with
id, path, language, and optional duration_seconds fields. Transcript text is
written only as structured JSON on stdout.
"""

private func parse(arguments: [String]) throws -> Options {
    var modelDirectory: URL?
    var manifest: URL?
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]
        guard index + 1 < arguments.count else {
            throw ProbeError.usage("missing value for \(argument)")
        }
        let value = arguments[index + 1]

        switch argument {
        case "--model-dir":
            modelDirectory = URL(fileURLWithPath: value)
        case "--manifest":
            manifest = URL(fileURLWithPath: value)
        default:
            throw ProbeError.usage("unknown argument: \(argument)")
        }
        index += 2
    }

    guard let modelDirectory, let manifest else {
        throw ProbeError.usage(helpText)
    }
    return Options(modelDirectory: modelDirectory, manifest: manifest)
}

private func requireFile(_ path: String) throws {
    guard FileManager.default.fileExists(atPath: path) else {
        throw ProbeError.missingModelFile(path)
    }
}

private func makeRecognizer(model: String, tokens: String) -> SherpaOnnxOfflineRecognizer {
    let senseVoice = sherpaOnnxOfflineSenseVoiceModelConfig(
        model: model,
        language: "auto",
        useInverseTextNormalization: true
    )
    let modelConfig = sherpaOnnxOfflineModelConfig(
        tokens: tokens,
        numThreads: 1,
        provider: "cpu",
        debug: 0,
        senseVoice: senseVoice
    )
    let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80)
    var config = sherpaOnnxOfflineRecognizerConfig(
        featConfig: featConfig,
        modelConfig: modelConfig,
        decodingMethod: "greedy_search"
    )
    return SherpaOnnxOfflineRecognizer(config: &config)
}

private func loadMono16kWav(_ url: URL) throws -> (samples: [Float], sampleRate: Int, durationSeconds: Double) {
    guard url.pathExtension.lowercased() == "wav" else {
        throw ProbeError.unsupportedAudio("audio is not WAV: \(url.path)")
    }

    let audioFile = try AVAudioFile(forReading: url)
    let format = audioFile.processingFormat
    guard Int(format.sampleRate.rounded()) == 16_000 else {
        throw ProbeError.unsupportedAudio("audio is not 16kHz: \(url.path)")
    }
    guard format.channelCount == 1 else {
        throw ProbeError.unsupportedAudio("audio is not mono: \(url.path)")
    }
    guard audioFile.length <= AVAudioFramePosition(AVAudioFrameCount.max) else {
        throw ProbeError.unsupportedAudio("audio is too long to buffer: \(url.path)")
    }
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audioFile.length)) else {
        throw ProbeError.unsupportedAudio("failed to allocate audio buffer: \(url.path)")
    }

    try audioFile.read(into: buffer)
    guard let channel = buffer.floatChannelData?[0] else {
        throw ProbeError.unsupportedAudio("audio could not be read as Float32 PCM: \(url.path)")
    }

    let count = Int(buffer.frameLength)
    return (
        Array(UnsafeBufferPointer(start: channel, count: count)),
        Int(format.sampleRate),
        Double(count) / format.sampleRate
    )
}

private func writeJSONLine<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
}

private func milliseconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Int {
    let duration = start.duration(to: end)
    let components = duration.components
    return Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000)
}

private func peakResidentSetSize() -> UInt64 {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return UInt64(max(usage.ru_maxrss, 0))
}

func activePeakDelta(baselineRSSBytes: UInt64, peakRSSBytes: UInt64) -> UInt64 {
    peakRSSBytes > baselineRSSBytes ? peakRSSBytes - baselineRSSBytes : 0
}

func chunkedSamples(_ samples: [Float], maximumFrameCount: Int) -> [[Float]] {
    precondition(maximumFrameCount > 0)
    return stride(from: 0, to: samples.count, by: maximumFrameCount).map {
        Array(samples[$0..<min($0 + maximumFrameCount, samples.count)])
    }
}

private func currentResidentSetSize() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
}

private func emptyToNil(_ value: String) -> String? {
    value.isEmpty ? nil : value
}

private func splitEvents(_ value: String) -> [String] {
    value
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

do {
    let code = try run(arguments: Array(CommandLine.arguments.dropFirst()))
    if code != 0 {
        exit(Int32(code))
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
