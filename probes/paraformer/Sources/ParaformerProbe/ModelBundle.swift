import CryptoKit
import Foundation

public struct ModelBundle: Sendable {
    public static let requiredFileNames = ["encoder.int8.onnx", "decoder.int8.onnx", "tokens.txt", "LICENSE"]

    public let directory: URL
    public let encoder: URL
    public let decoder: URL
    public let tokens: URL
    public let license: URL

    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case missingFile(String)
        case invalidManifest
        case checksumMismatch(String)

        public var description: String {
            switch self {
            case let .missingFile(file):
                return "required model file missing: \(file)"
            case .invalidManifest:
                return "manifest.sha256 must contain exactly one SHA-256 entry for each required model file"
            case let .checksumMismatch(file):
                return "checksum mismatch: \(file)"
            }
        }
    }

    public static func validate(at directory: URL) throws -> ModelBundle {
        let files = Dictionary(uniqueKeysWithValues: requiredFileNames.map {
            ($0, directory.appendingPathComponent($0))
        })
        let manifest = directory.appendingPathComponent("manifest.sha256")

        for file in requiredFileNames + ["manifest.sha256"] {
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(file).path) else {
                throw ValidationError.missingFile(file)
            }
        }

        let expected = try parseManifest(at: manifest)
        for file in requiredFileNames {
            let actual = try checksum(of: files[file]!)
            guard expected[file] == actual else {
                throw ValidationError.checksumMismatch(file)
            }
        }

        return ModelBundle(
            directory: directory,
            encoder: files["encoder.int8.onnx"]!,
            decoder: files["decoder.int8.onnx"]!,
            tokens: files["tokens.txt"]!,
            license: files["LICENSE"]!
        )
    }

    private static func parseManifest(at url: URL) throws -> [String: String] {
        var checksums: [String: String] = [:]
        for line in try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2,
                  fields[0].count == 64,
                  fields[0].allSatisfy({ $0.isHexDigit }),
                  requiredFileNames.contains(String(fields[1])),
                  checksums[String(fields[1])] == nil else {
                throw ValidationError.invalidManifest
            }
            checksums[String(fields[1])] = String(fields[0]).lowercased()
        }
        guard checksums.count == requiredFileNames.count else {
            throw ValidationError.invalidManifest
        }
        return checksums
    }

    private static func checksum(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
