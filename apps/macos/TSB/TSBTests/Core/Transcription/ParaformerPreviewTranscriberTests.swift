import CryptoKit
import XCTest
@testable import TSB

final class ParaformerPreviewTranscriberTests: XCTestCase {
    func testModelLocationRejectsMissingRequiredFile() throws {
        try withTemporaryParaformerDirectory { directory in
            try writeValidParaformerBundle(in: directory)
            try FileManager.default.removeItem(at: directory.appendingPathComponent("decoder.int8.onnx"))

            XCTAssertThrowsError(try ParaformerModelLocation(directory: directory)) { error in
                XCTAssertEqual(error as? ParaformerPreviewError, .missingModelFile("decoder.int8.onnx"))
            }
        }
    }

    func testModelLocationSeparatesChecksumMismatchFromMalformedManifest() throws {
        try withTemporaryParaformerDirectory { directory in
            try writeValidParaformerBundle(in: directory)
            try Data("changed".utf8).write(to: directory.appendingPathComponent("encoder.int8.onnx"))

            XCTAssertThrowsError(try ParaformerModelLocation(directory: directory)) { error in
                XCTAssertEqual(error as? ParaformerPreviewError, .checksumMismatch("encoder.int8.onnx"))
            }

            try "not-a-manifest\n".write(
                to: directory.appendingPathComponent("manifest.sha256"),
                atomically: true,
                encoding: .utf8
            )
            XCTAssertThrowsError(try ParaformerModelLocation(directory: directory)) { error in
                XCTAssertEqual(error as? ParaformerPreviewError, .invalidModelManifest)
            }
        }
    }

    func testModelLocationRejectsOversizedManifest() throws {
        try withTemporaryParaformerDirectory { directory in
            try writeValidParaformerBundle(in: directory)
            try Data(repeating: 0x20, count: 65_537)
                .write(to: directory.appendingPathComponent("manifest.sha256"))

            XCTAssertThrowsError(try ParaformerModelLocation(directory: directory)) { error in
                XCTAssertEqual(error as? ParaformerPreviewError, .modelManifestTooLarge)
            }
        }
    }

    func testResolvedLocationPrefersExplicitEnvironmentOverride() throws {
        try withTemporaryParaformerDirectory { root in
            let override = root.appendingPathComponent("override", isDirectory: true)
            let appSupport = root.appendingPathComponent("Application Support", isDirectory: true)
            try FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
            try writeValidParaformerBundle(in: override)

            let location = try ParaformerModelLocation.resolvedLocation(
                environment: ["TSB_PARAFORMER_MODEL_DIR": override.path],
                applicationSupportDirectory: appSupport
            )

            XCTAssertEqual(location.encoder.standardizedFileURL, override.appendingPathComponent("encoder.int8.onnx").standardizedFileURL)
        }
    }

    func testResolvedLocationUsesCanonicalApplicationSupportBundle() throws {
        try withTemporaryParaformerDirectory { root in
            let appSupport = root.appendingPathComponent("Application Support", isDirectory: true)
            let model = appSupport
                .appendingPathComponent("TSB/Models", isDirectory: true)
                .appendingPathComponent(ParaformerModelLocation.modelName, isDirectory: true)
            try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
            try writeValidParaformerBundle(in: model)

            let location = try ParaformerModelLocation.resolvedLocation(
                environment: [:],
                applicationSupportDirectory: appSupport
            )

            XCTAssertEqual(location.decoder.standardizedFileURL, model.appendingPathComponent("decoder.int8.onnx").standardizedFileURL)
        }
    }

    func testStatePublishesOnlyChangedFullPreview() {
        var state = ParaformerPreviewState()

        XCTAssertEqual(state.updatePartial("你"), "你")
        XCTAssertNil(state.updatePartial("你"))
        XCTAssertEqual(state.updatePartial("你好"), "你好")
    }

    func testStateKeepsCommittedEndpointsInOrder() {
        var state = ParaformerPreviewState()

        XCTAssertEqual(state.updatePartial("第一"), "第一")
        XCTAssertNil(state.commitEndpoint("第一"))
        XCTAssertEqual(state.updatePartial("第二"), "第一\n第二")
        XCTAssertNil(state.commitEndpoint("第二"))
        XCTAssertEqual(state.updatePartial("第三"), "第一\n第二\n第三")
    }

    func testFinishKeepsPartialWhenFinalDecoderTextIsEmptyAndResetsForReuse() {
        var state = ParaformerPreviewState()

        XCTAssertEqual(state.updatePartial("未对齐尾音"), "未对齐尾音")
        XCTAssertEqual(state.finish(""), "未对齐尾音")
        XCTAssertEqual(state.updatePartial("新会话"), "新会话")
    }

    func testFinishAppendsFinalTailAfterCommittedEndpoint() {
        var state = ParaformerPreviewState()

        _ = state.commitEndpoint("第一句")
        _ = state.updatePartial("尾声")

        XCTAssertEqual(state.finish("尾声完成"), "第一句\n尾声完成")
    }

    func testCancelClearsCommittedAndPartialText() {
        var state = ParaformerPreviewState()

        _ = state.commitEndpoint("旧句子")
        _ = state.updatePartial("旧尾音")
        state.cancel()

        XCTAssertEqual(state.updatePartial("新句子"), "新句子")
    }

    func testEmptyInputProducesNoPreviewOrFinalText() {
        var state = ParaformerPreviewState()

        XCTAssertNil(state.updatePartial(""))
        XCTAssertNil(state.commitEndpoint(""))
        XCTAssertEqual(state.finish(""), "")
    }

    func testFinalPaddingCoversParaformerReadinessWindow() {
        XCTAssertEqual(ParaformerPreviewTranscriber.finalPaddingSamples, 16_000)
    }
}

private func withTemporaryParaformerDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ParaformerPreviewTranscriberTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

private func writeValidParaformerBundle(in directory: URL) throws {
    for file in ParaformerModelLocation.requiredFileNames {
        try Data(file.utf8).write(to: directory.appendingPathComponent(file))
    }
    let manifest = try ParaformerModelLocation.requiredFileNames.map { file in
        let data = try Data(contentsOf: directory.appendingPathComponent(file))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + "  " + file
    }.joined(separator: "\n") + "\n"
    try manifest.write(
        to: directory.appendingPathComponent("manifest.sha256"),
        atomically: true,
        encoding: .utf8
    )
}
