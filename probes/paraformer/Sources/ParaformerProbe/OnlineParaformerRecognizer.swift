import Foundation
import SherpaOnnx

public enum OnlineRecognizerEvent: Equatable, Sendable {
    case partial(String)
    case final(String)
}

struct OnlineRecognizerState {
    private var lastPartial = ""

    mutating func partial(_ text: String) -> [OnlineRecognizerEvent] {
        guard !text.isEmpty, text != lastPartial else { return [] }
        lastPartial = text
        return [.partial(text)]
    }

    mutating func endpoint(_ text: String) -> [OnlineRecognizerEvent] {
        defer { cancel() }
        return text.isEmpty ? [] : [.final(text)]
    }

    mutating func finish(_ text: String) -> [OnlineRecognizerEvent] {
        defer { cancel() }
        return text.isEmpty ? [] : [.final(text)]
    }

    mutating func cancel() {
        lastPartial = ""
    }
}

public actor OnlineParaformerRecognizer {
    public static let sampleRate = 16_000
    public static let finalPaddingSamples = 3_200

    private let recognizer: SherpaOnnxRecognizer
    private var state = OnlineRecognizerState()
    private var hasInput = false

    public init(modelBundle: ModelBundle) {
        let model = sherpaOnnxOnlineModelConfig(
            tokens: modelBundle.tokens.path,
            paraformer: sherpaOnnxOnlineParaformerModelConfig(
                encoder: modelBundle.encoder.path,
                decoder: modelBundle.decoder.path
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
        recognizer = SherpaOnnxRecognizer(config: &config)
    }

    /// Accepts a normalized Float32, 16 kHz mono PCM chunk.
    public func accept(samples: [Float]) -> [OnlineRecognizerEvent] {
        guard !samples.isEmpty else { return [] }
        hasInput = true
        recognizer.acceptWaveform(samples: samples, sampleRate: Self.sampleRate)
        return decodeAvailable()
    }

    public func finish() -> [OnlineRecognizerEvent] {
        guard hasInput else {
            cancel()
            return []
        }

        recognizer.acceptWaveform(
            samples: Array(repeating: 0, count: Self.finalPaddingSamples),
            sampleRate: Self.sampleRate
        )
        recognizer.inputFinished()
        var events = decodeAvailable()
        events += state.finish(recognizer.getResult().text)
        recognizer.reset()
        hasInput = false
        return events
    }

    public func cancel() {
        recognizer.reset()
        state.cancel()
        hasInput = false
    }

    private func decodeAvailable() -> [OnlineRecognizerEvent] {
        var events: [OnlineRecognizerEvent] = []
        while recognizer.isReady() {
            recognizer.decode()
            let text = recognizer.getResult().text
            if recognizer.isEndpoint() {
                events += state.endpoint(text)
                recognizer.reset()
            } else {
                events += state.partial(text)
            }
        }
        return events
    }
}
