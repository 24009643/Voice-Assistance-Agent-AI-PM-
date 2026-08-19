import XCTest
@testable import SenseVoiceProbe

final class ModelManifestTests: XCTestCase {
    func testLoadAcceptsSupportedLanguageLabelsAndOptionalDuration() throws {
        try withTemporaryManifestDirectory { directory in
            let mandarin = try existingFile("mandarin.wav", in: directory)
            let cantonese = try existingFile("cantonese.wav", in: directory)
            let mixed = try existingFile("mixed.wav", in: directory)
            let manifest = try writeManifest(
                [
                    #"{"id":"mandarin-1","path":"\#(mandarin.path)","language":"zh","duration_seconds":1.25}"#,
                    #"{"id":"cantonese-1","path":"\#(cantonese.path)","language":"yue"}"#,
                    #"{"id":"mixed-1","path":"\#(mixed.path)","language":"zh-en","duration_seconds":2.5}"#
                ],
                in: directory
            )

            let loaded = try ModelManifest.load(from: manifest)

            XCTAssertEqual(loaded.samples.count, 3)
            XCTAssertEqual(loaded.samples[0].id, "mandarin-1")
            XCTAssertEqual(loaded.samples[0].language, "zh")
            XCTAssertEqual(loaded.samples[0].durationSeconds, 1.25)
            XCTAssertEqual(loaded.samples[1].language, "yue")
            XCTAssertNil(loaded.samples[1].durationSeconds)
            XCTAssertEqual(loaded.samples[2].language, "zh-en")
        }
    }

    func testLoadRejectsMissingAudioFile() throws {
        try withTemporaryManifestDirectory { directory in
            let missing = directory.appendingPathComponent("missing.wav")
            let manifest = try writeManifest(
                [#"{"id":"sample-1","path":"\#(missing.path)","language":"zh"}"#],
                in: directory
            )

            XCTAssertThrowsError(try ModelManifest.load(from: manifest)) { error in
                XCTAssertEqual(error as? ModelManifest.ValidationError, .missingFile(id: "sample-1", path: missing.path))
            }
        }
    }

    func testLoadRejectsNonWavAudioFile() throws {
        try withTemporaryManifestDirectory { directory in
            let audio = try existingFile("sample.m4a", in: directory)
            let manifest = try writeManifest(
                [#"{"id":"sample-1","path":"\#(audio.path)","language":"zh"}"#],
                in: directory
            )

            XCTAssertThrowsError(try ModelManifest.load(from: manifest)) { error in
                XCTAssertEqual(error as? ModelManifest.ValidationError, .nonWavFile(id: "sample-1", path: audio.path))
            }
        }
    }

    func testLoadRejectsMissingLanguageLabel() throws {
        try withTemporaryManifestDirectory { directory in
            let audio = try existingFile("sample.wav", in: directory)
            let manifest = try writeManifest(
                [#"{"id":"sample-1","path":"\#(audio.path)","language":""}"#],
                in: directory
            )

            XCTAssertThrowsError(try ModelManifest.load(from: manifest)) { error in
                XCTAssertEqual(error as? ModelManifest.ValidationError, .missingLanguage(id: "sample-1"))
            }
        }
    }

    func testLoadRejectsDuplicateSampleIDs() throws {
        try withTemporaryManifestDirectory { directory in
            let first = try existingFile("first.wav", in: directory)
            let second = try existingFile("second.wav", in: directory)
            let manifest = try writeManifest(
                [
                    #"{"id":"sample-1","path":"\#(first.path)","language":"zh"}"#,
                    #"{"id":"sample-1","path":"\#(second.path)","language":"yue"}"#
                ],
                in: directory
            )

            XCTAssertThrowsError(try ModelManifest.load(from: manifest)) { error in
                XCTAssertEqual(error as? ModelManifest.ValidationError, .duplicateID("sample-1"))
            }
        }
    }
}

private func withTemporaryManifestDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SenseVoiceProbeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

private func existingFile(_ name: String, in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent(name)
    try Data([0]).write(to: url)
    return url
}

private func writeManifest(_ lines: [String], in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent("manifest.jsonl")
    try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    return url
}
