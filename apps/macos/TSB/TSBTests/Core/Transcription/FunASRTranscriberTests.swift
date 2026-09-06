import CryptoKit
import Darwin
import XCTest
@testable import TSB

final class FunASRTranscriberTests: XCTestCase {
    func testDevelopmentLocationRequiresBothPaths() throws {
        XCTAssertThrowsError(try FunASRRuntimeLocation.developmentLocation(environment: [:]))
        XCTAssertThrowsError(try FunASRRuntimeLocation.developmentLocation(environment: [
            "TSB_FUNASR_CLI_PATH": "/tmp/funasr"
        ]))
    }

    func testDevelopmentLocationResolvesRequiredFiles() throws {
        try withFunASRFixture { executable, models in
            let location = try FunASRRuntimeLocation.developmentLocation(environment: [
                "TSB_FUNASR_CLI_PATH": executable.path,
                "TSB_FUNASR_MODEL_DIR": models.path
            ])

            XCTAssertEqual(location.executable.standardizedFileURL, executable.standardizedFileURL)
            XCTAssertEqual(location.encoder.lastPathComponent, "funasr-encoder-f16.gguf")
            XCTAssertEqual(location.languageModel.lastPathComponent, "qwen3-0.6b-q8_0.gguf")
            XCTAssertEqual(location.vad.lastPathComponent, "fsmn-vad.gguf")
        }
    }

    func testResolvedLocationPrefersEnvironmentOverride() throws {
        try withFunASRFixture { executable, models in
            let location = try FunASRRuntimeLocation.resolvedLocation(
                environment: [
                    "TSB_FUNASR_CLI_PATH": executable.path,
                    "TSB_FUNASR_MODEL_DIR": models.path
                ],
                applicationSupportDirectory: URL(fileURLWithPath: "/missing")
            )

            XCTAssertEqual(location.executable.standardizedFileURL, executable.standardizedFileURL)
            XCTAssertEqual(location.encoder.deletingLastPathComponent().standardizedFileURL, models.standardizedFileURL)
        }
    }

    func testResolvedLocationUsesCanonicalApplicationSupportBundle() throws {
        let fixture = try makeFunASRFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let applicationSupport = fixture.root.appendingPathComponent("Application Support", isDirectory: true)
        let canonicalModels = applicationSupport
            .appendingPathComponent("TSB/Models", isDirectory: true)
            .appendingPathComponent("funasr-nano", isDirectory: true)
        let canonicalRuntime = applicationSupport
            .appendingPathComponent("TSB/Runtimes/funasr-nano", isDirectory: true)
        try FileManager.default.createDirectory(
            at: canonicalModels.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: canonicalRuntime, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture.models, to: canonicalModels)
        let canonicalExecutable = canonicalRuntime.appendingPathComponent("llama-funasr-cli")
        try FileManager.default.copyItem(at: fixture.executable, to: canonicalExecutable)
        try "\(funASRSHA256(canonicalExecutable))  llama-funasr-cli\n".write(
            to: canonicalRuntime.appendingPathComponent("manifest.sha256"),
            atomically: true,
            encoding: .utf8
        )

        let location = try FunASRRuntimeLocation.resolvedLocation(
            environment: [:],
            applicationSupportDirectory: applicationSupport
        )

        XCTAssertEqual(location.executable.standardizedFileURL, canonicalExecutable.standardizedFileURL)
        XCTAssertEqual(location.encoder.deletingLastPathComponent().standardizedFileURL, canonicalModels.standardizedFileURL)
    }

    func testResolvedLocationIgnoresEmptyOverridesButRejectsPartialOverride() throws {
        let fixture = try makeCanonicalFunASRFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        XCTAssertNoThrow(try FunASRRuntimeLocation.resolvedLocation(
            environment: ["TSB_FUNASR_CLI_PATH": "", "TSB_FUNASR_MODEL_DIR": ""],
            applicationSupportDirectory: fixture.applicationSupport
        ))
        XCTAssertThrowsError(try FunASRRuntimeLocation.resolvedLocation(
            environment: ["TSB_FUNASR_CLI_PATH": fixture.executable.path],
            applicationSupportDirectory: fixture.applicationSupport
        ))
    }

    func testParseTrimsTranscriptAndRejectsEmptyOutput() throws {
        XCTAssertEqual(try FunASRTranscriber.parseOutput(Data("  hello TSB \n".utf8)), "hello TSB")
        XCTAssertThrowsError(try FunASRTranscriber.parseOutput(Data(" \n".utf8)))
    }

    func testChildProcessUsesDirectArgumentsAndDoesNotInheritSecrets() throws {
        try withFunASRFixture { executable, models in
            let location = try FunASRRuntimeLocation.developmentLocation(environment: [
                "TSB_FUNASR_CLI_PATH": executable.path,
                "TSB_FUNASR_MODEL_DIR": models.path
            ])
            let audio = URL(fileURLWithPath: "/tmp/audio ; echo leaked.wav")

            XCTAssertEqual(FunASRTranscriber.arguments(location: location, wavURL: audio)[5], audio.path)
            XCTAssertNil(FunASRTranscriber.childEnvironment()["DEEPSEEK_API_KEY"])
        }
    }

    func testOversizedChildOutputFailsClosed() async throws {
        let fixture = try makeFunASRFixture(
            executableContents: "#!/bin/sh\n/usr/bin/yes x | /usr/bin/head -c 1100000\n"
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let location = try FunASRRuntimeLocation.developmentLocation(environment: fixture.environment)

        do {
            _ = try await FunASRTranscriber(location: location).transcribe(
                wavURL: URL(fileURLWithPath: "/tmp/audio.wav")
            )
            XCTFail("Expected output limit failure")
        } catch let error as FunASRTranscriberError {
            XCTAssertEqual(error, .outputTooLarge)
        }
    }

    func testSuccessfulChildOutputBecomesFunASRResult() async throws {
        let fixture = try makeFunASRFixture(executableContents: "#!/bin/sh\necho '中英 mixed final'\n")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let location = try FunASRRuntimeLocation.developmentLocation(environment: fixture.environment)

        let result = try await FunASRTranscriber(location: location).transcribe(
            wavURL: URL(fileURLWithPath: "/tmp/audio.wav")
        )

        XCTAssertEqual(result.text, "中英 mixed final")
        XCTAssertEqual(result.finalSource, .funASR)
    }

    func testCancellingTranscriptionStopsChildProcess() async throws {
        let pidURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TSB-FunASR-PID-\(UUID().uuidString)")
        let fixture = try makeFunASRFixture(
            executableContents: "#!/bin/sh\ntrap '' TERM\necho $$ > \"" + pidURL.path + "\"\nexec /bin/sleep 30\n"
        )
        defer {
            try? FileManager.default.removeItem(at: fixture.root)
            try? FileManager.default.removeItem(at: pidURL)
        }
        let location = try FunASRRuntimeLocation.developmentLocation(environment: fixture.environment)
        let task = Task {
            try await FunASRTranscriber(location: location).transcribe(
                wavURL: URL(fileURLWithPath: "/tmp/audio.wav")
            )
        }
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: pidURL.path) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let pid = try XCTUnwrap(Int32(String(contentsOf: pidURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertEqual(kill(pid, 0), -1)
        }
    }

    @MainActor
    func testFinalTranscriptionUsesPrimaryWithoutFallback() async throws {
        var fallbackCalled = false

        let result = try await AppController.transcribeFinal(
            url: URL(fileURLWithPath: "/tmp/audio.wav"),
            primary: { _ in Self.result("primary") },
            fallback: { _ in
                fallbackCalled = true
                return Self.result("fallback")
            }
        )

        XCTAssertEqual(result.text, "primary")
        XCTAssertFalse(fallbackCalled)
    }

    @MainActor
    func testFinalTranscriptionFallsBackWhenPrimaryFails() async throws {
        let result = try await AppController.transcribeFinal(
            url: URL(fileURLWithPath: "/tmp/audio.wav"),
            primary: { _ in throw StubError.failed },
            fallback: { _ in Self.result("fallback") }
        )

        XCTAssertEqual(result.text, "fallback")
    }

    @MainActor
    func testFinalTranscriptionDoesNotFallbackAfterCancellation() async {
        var fallbackCalled = false
        let task = Task { @MainActor in
            try await AppController.transcribeFinal(
                url: URL(fileURLWithPath: "/tmp/audio.wav"),
                primary: { _ in
                    try await Task.sleep(for: .seconds(10))
                    return Self.result("late")
                },
                fallback: { _ in
                    fallbackCalled = true
                    return Self.result("fallback")
                }
            )
        }
        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertFalse(fallbackCalled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static func result(_ text: String) -> TranscriptionResult {
        TranscriptionResult(text: text, detectedLanguage: nil, eventTags: [], latencyMilliseconds: 1)
    }
}

private enum StubError: Error {
    case failed
}

private func withFunASRFixture(_ body: (URL, URL) throws -> Void) throws {
    let fixture = try makeFunASRFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try body(fixture.executable, fixture.models)
}

private struct FunASRFixture {
    let root: URL
    let executable: URL
    let models: URL

    var environment: [String: String] {
        ["TSB_FUNASR_CLI_PATH": executable.path, "TSB_FUNASR_MODEL_DIR": models.path]
    }
}

private struct CanonicalFunASRFixture {
    let root: URL
    let applicationSupport: URL
    let executable: URL
}

private func makeCanonicalFunASRFixture() throws -> CanonicalFunASRFixture {
    let fixture = try makeFunASRFixture()
    let applicationSupport = fixture.root.appendingPathComponent("Application Support", isDirectory: true)
    let canonicalModels = applicationSupport
        .appendingPathComponent("TSB/Models/funasr-nano", isDirectory: true)
    let canonicalRuntime = applicationSupport
        .appendingPathComponent("TSB/Runtimes/funasr-nano", isDirectory: true)
    try FileManager.default.createDirectory(at: canonicalModels.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: canonicalRuntime, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: fixture.models, to: canonicalModels)
    let canonicalExecutable = canonicalRuntime.appendingPathComponent("llama-funasr-cli")
    try FileManager.default.copyItem(at: fixture.executable, to: canonicalExecutable)
    try "\(funASRSHA256(canonicalExecutable))  llama-funasr-cli\n".write(
        to: canonicalRuntime.appendingPathComponent("manifest.sha256"),
        atomically: true,
        encoding: .utf8
    )
    return CanonicalFunASRFixture(
        root: fixture.root,
        applicationSupport: applicationSupport,
        executable: canonicalExecutable
    )
}

private func makeFunASRFixture(executableContents: String = "#!/bin/sh\n") throws -> FunASRFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("FunASRTranscriberTests-\(UUID().uuidString)", isDirectory: true)
    let executable = root.appendingPathComponent("llama-funasr-cli")
    let models = root.appendingPathComponent("models", isDirectory: true)
    try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)

    try Data(executableContents.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    for name in ["funasr-encoder-f16.gguf", "qwen3-0.6b-q8_0.gguf", "fsmn-vad.gguf"] {
        try Data(name.utf8).write(to: models.appendingPathComponent(name))
    }
    let manifest = ["funasr-encoder-f16.gguf", "qwen3-0.6b-q8_0.gguf", "fsmn-vad.gguf"]
        .map { "\(funASRSHA256(models.appendingPathComponent($0)))  \($0)" }
        .joined(separator: "\n")
    try (manifest + "\n").write(
        to: models.appendingPathComponent("manifest.sha256"),
        atomically: true,
        encoding: .utf8
    )
    return FunASRFixture(root: root, executable: executable, models: models)
}

private func funASRSHA256(_ url: URL) -> String {
    SHA256.hash(data: try! Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
}
