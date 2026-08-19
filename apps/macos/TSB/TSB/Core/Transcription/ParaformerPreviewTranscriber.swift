import Foundation
import SherpaOnnx

enum ParaformerPreviewError: Error, Equatable {
    case missingDevelopmentModelDirectory
    case missingModelFile(String)
    case invalidModelManifest
    case modelManifestTooLarge
    case checksumMismatch(String)
}

struct ParaformerModelLocation: Sendable {
    static let requiredFileNames = ["encoder.int8.onnx", "decoder.int8.onnx", "tokens.txt", "LICENSE"]

    let encoder: URL
    let decoder: URL
    let tokens: URL
    let license: URL
    let manifest: URL

    init(directory: URL) throws {
        encoder = directory.appendingPathComponent("encoder.int8.onnx")
        decoder = directory.appendingPathComponent("decoder.int8.onnx")
        tokens = directory.appendingPathComponent("tokens.txt")
        license = directory.appendingPathComponent("LICENSE")
        manifest = directory.appendingPathComponent("manifest.sha256")

        do {
            try ModelManifestValidator.validate(directory: directory, requiredFileNames: Self.requiredFileNames)
        } catch let error as ModelManifestValidationError {
            switch error {
            case let .missingFile(file): throw ParaformerPreviewError.missingModelFile(file)
            case .invalidManifest: throw ParaformerPreviewError.invalidModelManifest
            case .manifestTooLarge: throw ParaformerPreviewError.modelManifestTooLarge
            case let .checksumMismatch(file): throw ParaformerPreviewError.checksumMismatch(file)
            }
        }
    }

    static func developmentLocation(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ParaformerModelLocation {
        guard let path = environment["TSB_PARAFORMER_MODEL_DIR"], !path.isEmpty else {
            throw ParaformerPreviewError.missingDevelopmentModelDirectory
        }
        return try ParaformerModelLocation(directory: URL(fileURLWithPath: path, isDirectory: true))
    }
}

struct ParaformerPreviewState {
    private var committedSegments: [String] = []
    private var currentPartial = ""
    private var lastPublished = ""

    mutating func updatePartial(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        currentPartial = text
        return changedPreview()
    }

    mutating func commitEndpoint(_ text: String) -> String? {
        let segment = text.isEmpty ? currentPartial : text
        if !segment.isEmpty { committedSegments.append(segment) }
        currentPartial = ""
        return changedPreview()
    }

    mutating func finish(_ text: String) -> String {
        let tail = text.isEmpty ? currentPartial : text
        if !tail.isEmpty { committedSegments.append(tail) }
        currentPartial = ""
        let result = fullPreview
        cancel()
        return result
    }

    mutating func cancel() {
        committedSegments = []
        currentPartial = ""
        lastPublished = ""
    }

    private var fullPreview: String {
        (committedSegments + (currentPartial.isEmpty ? [] : [currentPartial])).joined(separator: "\n")
    }

    private mutating func changedPreview() -> String? {
        let preview = fullPreview
        guard !preview.isEmpty, preview != lastPublished else { return nil }
        lastPublished = preview
        return preview
    }
}

actor ParaformerPreviewTranscriber {
    static let sampleRate = 16_000
    static let finalPaddingSamples = 16_000

    private let location: ParaformerModelLocation
    private var recognizer: SherpaOnnxRecognizer
    private var state = ParaformerPreviewState()
    private var hasInput = false

    init(location: ParaformerModelLocation) {
        self.location = location
        recognizer = Self.makeRecognizer(location)
    }

    func accept(samples: [Float]) -> String? {
        guard !samples.isEmpty else { return nil }
        hasInput = true
        recognizer.acceptWaveform(samples: samples, sampleRate: Self.sampleRate)
        return decodeAvailable(resetAtEndpoint: true)
    }

    func finish() -> String {
        guard hasInput else {
            cancel()
            return ""
        }

        recognizer.acceptWaveform(
            samples: Array(repeating: 0, count: Self.finalPaddingSamples),
            sampleRate: Self.sampleRate
        )
        recognizer.inputFinished()
        _ = decodeAvailable(resetAtEndpoint: false)
        let result = state.finish(recognizer.getResult().text)
        recognizer = Self.makeRecognizer(location)
        hasInput = false
        return result
    }

    func cancel() {
        recognizer.reset()
        state.cancel()
        hasInput = false
    }

    private func decodeAvailable(resetAtEndpoint: Bool) -> String? {
        var latestPreview: String?
        while recognizer.isReady() {
            recognizer.decode()
            let text = recognizer.getResult().text
            if resetAtEndpoint && recognizer.isEndpoint() {
                if let preview = state.commitEndpoint(text) { latestPreview = preview }
                recognizer.reset()
            } else if let preview = state.updatePartial(text) {
                latestPreview = preview
            }
        }
        return latestPreview
    }

    private static func makeRecognizer(_ location: ParaformerModelLocation) -> SherpaOnnxRecognizer {
        let model = sherpaOnnxOnlineModelConfig(
            tokens: location.tokens.path,
            paraformer: sherpaOnnxOnlineParaformerModelConfig(
                encoder: location.encoder.path,
                decoder: location.decoder.path
            ),
            numThreads: 1,
            provider: "cpu",
            modelType: "paraformer"
        )
        let features = sherpaOnnxFeatureConfig(sampleRate: Self.sampleRate, featureDim: 80)
        var config = sherpaOnnxOnlineRecognizerConfig(
            featConfig: features,
            modelConfig: model,
            enableEndpoint: true,
            decodingMethod: "greedy_search"
        )
        return SherpaOnnxRecognizer(config: &config)
    }
}
