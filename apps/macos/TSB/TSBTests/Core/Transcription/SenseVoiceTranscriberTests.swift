import AVFoundation
import CryptoKit
import XCTest
@testable import TSB

final class SenseVoiceTranscriberTests: XCTestCase {
    func testModelLocationRejectsMissingFiles() throws {
        try withTemporaryDirectory { directory in
            XCTAssertThrowsError(try SenseVoiceModelLocation(directory: directory))
        }
    }

    func testModelLocationRejectsDigestMismatch() throws {
        try withTemporaryDirectory { directory in
            try writeModelFiles(in: directory)
            try "\(String(repeating: "0", count: 64))  model.int8.onnx\n\(sha256(of: directory.appendingPathComponent("tokens.txt")))  tokens.txt\n\(sha256(of: directory.appendingPathComponent("LICENSE")))  LICENSE\n"
                .write(to: directory.appendingPathComponent("manifest.sha256"), atomically: true, encoding: .utf8)

            XCTAssertThrowsError(try SenseVoiceModelLocation(directory: directory))
        }
    }

    func testModelLocationAcceptsExactRequiredManifest() throws {
        try withTemporaryDirectory { directory in
            try writeModelFiles(in: directory)
            try writeManifest(in: directory)

            let location = try SenseVoiceModelLocation(directory: directory)

            XCTAssertEqual(location.model.lastPathComponent, "model.int8.onnx")
            XCTAssertEqual(location.tokens.lastPathComponent, "tokens.txt")
        }
    }

    func testModelLocationRejectsOversizedManifestBeforeReadingIt() throws {
        try withTemporaryDirectory { directory in
            try writeModelFiles(in: directory)
            try Data(repeating: 0x20, count: 65_537)
                .write(to: directory.appendingPathComponent("manifest.sha256"))

            XCTAssertThrowsError(try SenseVoiceModelLocation(directory: directory)) { error in
                XCTAssertEqual(error as? SenseVoiceTranscriberError, .modelManifestTooLarge)
            }
        }
    }

    func testUserTextDoesNotContainControlTags() {
        let parsed = SenseVoiceTranscriber.parse(
            text: "<|zh|><|Speech|>这是正文",
            language: "<|zh|>",
            event: "<|Speech|>, <|BGM|>"
        )

        XCTAssertEqual(parsed.text, "这是正文")
        XCTAssertEqual(parsed.detectedLanguage, "zh")
        XCTAssertEqual(parsed.eventTags, ["Speech", "BGM"])
    }

    func testChunkingPreservesEveryFrameInOrderWithoutOverlap() {
        let chunks = SenseVoiceTranscriber.chunkedSamples([0, 1, 2, 3, 4, 5, 6], maximumFrameCount: 3)

        XCTAssertEqual(chunks, [[0, 1, 2], [3, 4, 5], [6]])
        XCTAssertEqual(chunks.flatMap { $0 }, [0, 1, 2, 3, 4, 5, 6])
    }

    func testWAVValidationRejectsNonMonoOrNon16kAudio() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("stereo-44k.wav")
            try writeWAV(to: url, sampleRate: 44_100, channels: 2)

            XCTAssertThrowsError(try SenseVoiceTranscriber.loadMono16kWAV(url))
        }
    }

}
private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SenseVoiceTranscriberTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

private func writeModelFiles(in directory: URL) throws {
    try Data("model".utf8).write(to: directory.appendingPathComponent("model.int8.onnx"))
    try Data("tokens".utf8).write(to: directory.appendingPathComponent("tokens.txt"))
    try Data("license".utf8).write(to: directory.appendingPathComponent("LICENSE"))
}

private func writeManifest(in directory: URL) throws {
    let manifest = ["model.int8.onnx", "tokens.txt", "LICENSE"]
        .map { "\(sha256(of: directory.appendingPathComponent($0)))  \($0)" }
        .joined(separator: "\n")
    try (manifest + "\n").write(to: directory.appendingPathComponent("manifest.sha256"), atomically: true, encoding: .utf8)
}

private func sha256(of url: URL) -> String {
    let digest = SHA256.hash(data: try! Data(contentsOf: url))
    return digest.map { String(format: "%02x", $0) }.joined()
}

private func writeWAV(to url: URL, sampleRate: Double, channels: AVAudioChannelCount) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
    buffer.frameLength = 1
    try file.write(from: buffer)
}
