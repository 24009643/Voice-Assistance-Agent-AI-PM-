import AVFoundation
import CryptoKit
import Foundation
import SherpaOnnx

enum SenseVoiceTranscriberError: Error, Equatable {
    case missingDevelopmentModelDirectory
    case missingModelFile(String)
    case invalidModelManifest
    case modelManifestTooLarge
    case unsupportedAudio(String)
}

struct SenseVoiceModelLocation: Sendable {
    private static let requiredFileNames = ["model.int8.onnx", "tokens.txt", "LICENSE"]

    let model: URL
    let tokens: URL
    let license: URL
    let manifest: URL

    init(directory: URL) throws {
        model = directory.appendingPathComponent("model.int8.onnx")
        tokens = directory.appendingPathComponent("tokens.txt")
        license = directory.appendingPathComponent("LICENSE")
        manifest = directory.appendingPathComponent("manifest.sha256")

        for url in [model, tokens, license, manifest] where !FileManager.default.fileExists(atPath: url.path) {
            throw SenseVoiceTranscriberError.missingModelFile(url.lastPathComponent)
        }
        try Self.verifyManifest(at: manifest, in: directory)
    }

    static func developmentLocation(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> SenseVoiceModelLocation {
        guard let path = environment["TSB_SENSEVOICE_MODEL_DIR"], !path.isEmpty else {
            throw SenseVoiceTranscriberError.missingDevelopmentModelDirectory
        }
        return try SenseVoiceModelLocation(directory: URL(fileURLWithPath: path, isDirectory: true))
    }

    private static func verifyManifest(at manifest: URL, in directory: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: manifest.path)
        guard let size = attributes[.size] as? NSNumber, size.uint64Value <= 65_536 else {
            throw SenseVoiceTranscriberError.modelManifestTooLarge
        }
        let contents = try String(contentsOf: manifest, encoding: .utf8)
        var expectedDigests: [String: String] = [:]

        for line in contents.split(whereSeparator: { $0.isNewline }) {
            let fields = line.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            guard fields.count == 2,
                  fields[0].count == 64,
                  fields[0].allSatisfy({ $0.isHexDigit })
            else {
                throw SenseVoiceTranscriberError.invalidModelManifest
            }

            let fileName = String(fields[1]).trimmingCharacters(in: .whitespaces)
            guard requiredFileNames.contains(fileName), expectedDigests[fileName] == nil else {
                throw SenseVoiceTranscriberError.invalidModelManifest
            }
            expectedDigests[fileName] = String(fields[0]).lowercased()
        }

        guard expectedDigests.count == requiredFileNames.count else {
            throw SenseVoiceTranscriberError.invalidModelManifest
        }

        for fileName in requiredFileNames {
            let actualDigest = SHA256.hash(data: try Data(contentsOf: directory.appendingPathComponent(fileName)))
                .map { String(format: "%02x", $0) }
                .joined()
            guard expectedDigests[fileName] == actualDigest else {
                throw SenseVoiceTranscriberError.invalidModelManifest
            }
        }
    }
}

struct TranscriptionResult: Equatable, Sendable {
    let text: String
    let detectedLanguage: String?
    let eventTags: [String]
    let latencyMilliseconds: Int
}

actor SenseVoiceTranscriber {
    private static let sampleRate = 16_000
    private static let maximumFrameCount = sampleRate * 30

    private let recognizer: SherpaOnnxOfflineRecognizer

    init(location: SenseVoiceModelLocation) throws {
        recognizer = Self.makeRecognizer(model: location.model.path, tokens: location.tokens.path)
    }

    func transcribe(wavURL: URL) async throws -> TranscriptionResult {
        let audio = try Self.loadMono16kWAV(wavURL)
        let startedAt = ContinuousClock.now
        var texts: [String] = []
        var languages: [String] = []
        var events: [String] = []

        for chunk in Self.chunkedSamples(audio.samples, maximumFrameCount: Self.maximumFrameCount) {
            let decoded = autoreleasepool { () -> (text: String, language: String, event: String) in
                let result = recognizer.decode(samples: chunk, sampleRate: audio.sampleRate)
                return (result.text, result.lang, result.event)
            }
            let parsed = Self.parse(text: decoded.text, language: decoded.language, event: decoded.event)
            if !parsed.text.isEmpty { texts.append(parsed.text) }
            if let language = parsed.detectedLanguage { languages.append(language) }
            events.append(contentsOf: parsed.eventTags)
        }

        return TranscriptionResult(
            text: texts.joined(separator: "\n"),
            detectedLanguage: languages.first,
            eventTags: Self.orderedUnique(events),
            latencyMilliseconds: Self.milliseconds(since: startedAt)
        )
    }

    nonisolated static func parse(text: String, language: String, event: String) -> TranscriptionResult {
        TranscriptionResult(
            text: text.replacingOccurrences(of: #"<\|[^|>]+\|>"#, with: "", options: .regularExpression),
            detectedLanguage: normalizedControlTag(language),
            eventTags: event
                .split(separator: ",")
                .compactMap { normalizedControlTag(String($0)) },
            latencyMilliseconds: 0
        )
    }

    nonisolated static func chunkedSamples(_ samples: [Float], maximumFrameCount: Int) -> [[Float]] {
        precondition(maximumFrameCount > 0)
        return stride(from: 0, to: samples.count, by: maximumFrameCount).map {
            Array(samples[$0..<min($0 + maximumFrameCount, samples.count)])
        }
    }

    nonisolated static func loadMono16kWAV(_ url: URL) throws -> (samples: [Float], sampleRate: Int) {
        guard url.pathExtension.lowercased() == "wav" else {
            throw SenseVoiceTranscriberError.unsupportedAudio("audio is not WAV")
        }

        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        guard Int(format.sampleRate.rounded()) == sampleRate, format.channelCount == 1 else {
            throw SenseVoiceTranscriberError.unsupportedAudio("audio must be 16kHz mono WAV")
        }
        guard audioFile.length <= AVAudioFramePosition(AVAudioFrameCount.max),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audioFile.length))
        else {
            throw SenseVoiceTranscriberError.unsupportedAudio("audio is too long to buffer")
        }

        try audioFile.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else {
            throw SenseVoiceTranscriberError.unsupportedAudio("audio could not be read as Float32 PCM")
        }
        return (Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))), sampleRate)
    }

    private static func makeRecognizer(model: String, tokens: String) -> SherpaOnnxOfflineRecognizer {
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
        let featureConfig = sherpaOnnxFeatureConfig(sampleRate: sampleRate, featureDim: 80)
        var config = sherpaOnnxOfflineRecognizerConfig(
            featConfig: featureConfig,
            modelConfig: modelConfig,
            decodingMethod: "greedy_search"
        )
        return SherpaOnnxOfflineRecognizer(config: &config)
    }

    private nonisolated static func normalizedControlTag(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let unwrapped: String
        if trimmed.hasPrefix("<|"), trimmed.hasSuffix("|>"), trimmed.count >= 4 {
            unwrapped = String(trimmed.dropFirst(2).dropLast(2))
        } else {
            unwrapped = trimmed
        }
        return unwrapped.isEmpty ? nil : unwrapped
    }

    private nonisolated static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private nonisolated static func milliseconds(since startedAt: ContinuousClock.Instant) -> Int {
        let components = startedAt.duration(to: .now).components
        return Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000)
    }
}
