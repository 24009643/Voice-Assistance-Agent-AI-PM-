import Foundation
import Darwin

enum FunASRTranscriberError: Error, Equatable {
    case missingDevelopmentConfiguration
    case missingFile(String)
    case executableUnavailable
    case invalidModelManifest
    case modelManifestTooLarge
    case processFailed(Int32)
    case outputTooLarge
    case timedOut
    case invalidOutput
}

struct FunASRRuntimeLocation: Sendable {
    static let modelName = "funasr-nano"
    static let runtimeName = "funasr-nano"
    static let executableName = "llama-funasr-cli"
    private static let requiredModelFiles = [
        "funasr-encoder-f16.gguf",
        "qwen3-0.6b-q8_0.gguf",
        "fsmn-vad.gguf"
    ]
    let executable: URL
    let encoder: URL
    let languageModel: URL
    let vad: URL

    static func developmentLocation(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> FunASRRuntimeLocation {
        guard let executablePath = environment["TSB_FUNASR_CLI_PATH"], !executablePath.isEmpty,
              let modelPath = environment["TSB_FUNASR_MODEL_DIR"], !modelPath.isEmpty else {
            throw FunASRTranscriberError.missingDevelopmentConfiguration
        }
        return try location(
            executable: URL(fileURLWithPath: executablePath),
            modelDirectory: URL(fileURLWithPath: modelPath, isDirectory: true)
        )
    }

    static func resolvedLocation(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        applicationSupportDirectory: URL? = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
    ) throws -> FunASRRuntimeLocation {
        let executableOverride = environment["TSB_FUNASR_CLI_PATH"].flatMap { $0.isEmpty ? nil : $0 }
        let modelOverride = environment["TSB_FUNASR_MODEL_DIR"].flatMap { $0.isEmpty ? nil : $0 }
        if executableOverride != nil || modelOverride != nil {
            guard executableOverride != nil, modelOverride != nil else {
                throw FunASRTranscriberError.missingDevelopmentConfiguration
            }
            return try developmentLocation(environment: environment)
        }
        guard let applicationSupportDirectory else {
            throw FunASRTranscriberError.missingDevelopmentConfiguration
        }
        let modelDirectory = applicationSupportDirectory
            .appendingPathComponent("TSB/Models", isDirectory: true)
            .appendingPathComponent(modelName, isDirectory: true)
        let runtimeDirectory = applicationSupportDirectory
            .appendingPathComponent("TSB/Runtimes", isDirectory: true)
            .appendingPathComponent(runtimeName, isDirectory: true)
        try validateManifest(directory: runtimeDirectory, requiredFiles: [executableName])
        return try location(
            executable: runtimeDirectory.appendingPathComponent(executableName),
            modelDirectory: modelDirectory
        )
    }

    private static func location(executable: URL, modelDirectory: URL) throws -> FunASRRuntimeLocation {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw FunASRTranscriberError.executableUnavailable
        }
        try validateManifest(directory: modelDirectory, requiredFiles: requiredModelFiles)
        return FunASRRuntimeLocation(
            executable: executable,
            encoder: modelDirectory.appendingPathComponent(requiredModelFiles[0]),
            languageModel: modelDirectory.appendingPathComponent(requiredModelFiles[1]),
            vad: modelDirectory.appendingPathComponent(requiredModelFiles[2])
        )
    }

    private static func validateManifest(directory: URL, requiredFiles: [String]) throws {
        do {
            try ModelManifestValidator.validate(directory: directory, requiredFileNames: requiredFiles)
        } catch let error as ModelManifestValidationError {
            switch error {
            case let .missingFile(file): throw FunASRTranscriberError.missingFile(file)
            case .manifestTooLarge: throw FunASRTranscriberError.modelManifestTooLarge
                case .invalidManifest, .checksumMismatch: throw FunASRTranscriberError.invalidModelManifest
            }
        }
    }
}

actor FunASRTranscriber {
    private static let maximumOutputBytes = 1_048_576
    private let location: FunASRRuntimeLocation

    init(location: FunASRRuntimeLocation) {
        self.location = location
    }

    func transcribe(wavURL: URL) async throws -> TranscriptionResult {
        let startedAt = ContinuousClock.now
        let handle = try FunASRProcessHandle(
            executable: location.executable,
            arguments: Self.arguments(location: location, wavURL: wavURL),
            environment: Self.childEnvironment()
        )
        let data = try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask { try handle.run(maximumOutputBytes: Self.maximumOutputBytes) }
                group.addTask {
                    try await Task.sleep(for: .seconds(30))
                    throw FunASRTranscriberError.timedOut
                }
                do {
                    let output = try await group.next()!
                    group.cancelAll()
                    return output
                } catch {
                    handle.terminate()
                    group.cancelAll()
                    throw error
                }
            }
        } onCancel: {
            handle.terminate()
        }
        let elapsed = startedAt.duration(to: .now).components
        return TranscriptionResult(
            text: try Self.parseOutput(data),
            detectedLanguage: nil,
            eventTags: [],
            latencyMilliseconds: Int(elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000),
            finalSource: .funASR
        )
    }

    nonisolated static func parseOutput(_ data: Data) throws -> String {
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            throw FunASRTranscriberError.invalidOutput
        }
        return output
    }

    nonisolated static func arguments(location: FunASRRuntimeLocation, wavURL: URL) -> [String] {
        [
            "--enc", location.encoder.path,
            "-m", location.languageModel.path,
            "-a", wavURL.path,
            "--vad", location.vad.path
        ]
    }

    nonisolated static func childEnvironment() -> [String: String] {
        ["LANG": "en_US.UTF-8", "TMPDIR": FileManager.default.temporaryDirectory.path]
    }
}

private final class FunASRProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private let output = Pipe()
    private var cancellationRequested = false

    init(executable: URL, arguments: [String], environment: [String: String]) throws {
        process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
    }

    func run(maximumOutputBytes: Int) throws -> Data {
        lock.lock()
        if cancellationRequested {
            lock.unlock()
            throw CancellationError()
        }
        do {
            try process.run()
            lock.unlock()
        } catch {
            lock.unlock()
            throw error
        }

        var data = Data()
        while let chunk = try output.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
            guard data.count <= maximumOutputBytes - chunk.count else {
                terminate()
                process.waitUntilExit()
                throw FunASRTranscriberError.outputTooLarge
            }
            data.append(chunk)
        }
        process.waitUntilExit()
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            throw FunASRTranscriberError.processFailed(process.terminationStatus)
        }
        return data
    }

    func terminate() {
        let runningProcess: Process? = lock.withLock {
            cancellationRequested = true
            return process.isRunning ? process : nil
        }
        runningProcess?.terminate()
        guard let runningProcess else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            if runningProcess.isRunning {
                kill(runningProcess.processIdentifier, SIGKILL)
            }
        }
    }
}
