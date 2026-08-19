import CryptoKit
import Foundation
import XCTest
@testable import ParaformerProbe

final class ModelBundleTests: XCTestCase {
    func testValidateAcceptsRequiredFilesWithMatchingManifest() throws {
        try withTemporaryModelDirectory { directory in
            try writeValidModelBundle(in: directory)

            let bundle = try ModelBundle.validate(at: directory)

            XCTAssertEqual(bundle.encoder.lastPathComponent, "encoder.int8.onnx")
            XCTAssertEqual(bundle.decoder.lastPathComponent, "decoder.int8.onnx")
            XCTAssertEqual(bundle.tokens.lastPathComponent, "tokens.txt")
        }
    }

    func testValidateRejectsEachMissingRequiredFile() throws {
        for file in ModelBundle.requiredFileNames + ["manifest.sha256"] {
            try withTemporaryModelDirectory { directory in
                try writeValidModelBundle(in: directory)
                try FileManager.default.removeItem(at: directory.appendingPathComponent(file))

                XCTAssertThrowsError(try ModelBundle.validate(at: directory)) { error in
                    XCTAssertEqual(error as? ModelBundle.ValidationError, .missingFile(file))
                }
            }
        }
    }

    func testValidateRejectsChecksumMismatchForEachRequiredFile() throws {
        for file in ModelBundle.requiredFileNames {
            try withTemporaryModelDirectory { directory in
                try writeValidModelBundle(in: directory)
                try Data("changed".utf8).write(to: directory.appendingPathComponent(file))

                XCTAssertThrowsError(try ModelBundle.validate(at: directory)) { error in
                    XCTAssertEqual(error as? ModelBundle.ValidationError, .checksumMismatch(file))
                }
            }
        }
    }
}

private func withTemporaryModelDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ParaformerProbeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

private func writeValidModelBundle(in directory: URL) throws {
    for file in ModelBundle.requiredFileNames {
        try Data(file.utf8).write(to: directory.appendingPathComponent(file))
    }

    let manifest = try ModelBundle.requiredFileNames.map { file in
        let data = try Data(contentsOf: directory.appendingPathComponent(file))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + "  " + file
    }.joined(separator: "\n") + "\n"
    try manifest.write(to: directory.appendingPathComponent("manifest.sha256"), atomically: true, encoding: .utf8)
}
