import Foundation
import XCTest
@testable import TSB

final class DebugAudioFinalizerTests: XCTestCase {
    func testEnabledDebugArchiveMovesSourceAndPreservesBytes() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("source.wav")
            let archive = root.appendingPathComponent("Debug Audio", isDirectory: true)
            let bytes = Data([0x52, 0x49, 0x46, 0x46])
            try bytes.write(to: source)
            let sessionID = SessionID(rawValue: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!)
            let finalizer = DebugAudioFinalizer(
                isDebugBuild: true,
                environment: ["TSB_RETAIN_DEBUG_AUDIO": "1"],
                archiveDirectory: archive
            )

            try finalizer.finalize(source, sessionID: sessionID)

            let destination = archive.appendingPathComponent("11111111-2222-3333-4444-555555555555.wav")
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
            XCTAssertEqual(try Data(contentsOf: destination), bytes)
        }
    }

    func testReleaseBuildDeletesEvenWhenEnvironmentOptInIsSet() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("source.wav")
            let archive = root.appendingPathComponent("DebugAudio", isDirectory: true)
            try Data([0x01]).write(to: source)
            let finalizer = DebugAudioFinalizer(
                isDebugBuild: false,
                environment: ["TSB_RETAIN_DEBUG_AUDIO": "1"],
                archiveDirectory: archive
            )

            try finalizer.finalize(source, sessionID: SessionID(rawValue: UUID()))

            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
        }
    }

    func testDebugBuildDeletesWithoutEnvironmentOptIn() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("source.wav")
            let archive = root.appendingPathComponent("DebugAudio", isDirectory: true)
            try Data([0x01]).write(to: source)
            let finalizer = DebugAudioFinalizer(
                isDebugBuild: true,
                environment: [:],
                archiveDirectory: archive
            )

            try finalizer.finalize(source, sessionID: SessionID(rawValue: UUID()))

            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
        }
    }
}

private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("DebugAudioFinalizerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}
