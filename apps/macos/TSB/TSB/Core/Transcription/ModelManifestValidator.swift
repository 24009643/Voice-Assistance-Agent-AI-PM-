import CryptoKit
import Foundation

enum ModelManifestValidationError: Error, Equatable {
    case missingFile(String)
    case invalidManifest
    case manifestTooLarge
    case checksumMismatch(String)
}

enum ModelManifestValidator {
    static func validate(directory: URL, requiredFileNames: [String]) throws {
        let manifest = directory.appendingPathComponent("manifest.sha256")
        for fileName in requiredFileNames + [manifest.lastPathComponent]
        where !FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path) {
            throw ModelManifestValidationError.missingFile(fileName)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: manifest.path)
        guard let size = attributes[.size] as? NSNumber, size.uint64Value <= 65_536 else {
            throw ModelManifestValidationError.manifestTooLarge
        }

        var expectedDigests: [String: String] = [:]
        for line in try String(contentsOf: manifest, encoding: .utf8).split(whereSeparator: { $0.isNewline }) {
            let fields = line.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            guard fields.count == 2,
                  fields[0].count == 64,
                  fields[0].allSatisfy({ $0.isHexDigit })
            else {
                throw ModelManifestValidationError.invalidManifest
            }

            let fileName = String(fields[1]).trimmingCharacters(in: .whitespaces)
            guard requiredFileNames.contains(fileName), expectedDigests[fileName] == nil else {
                throw ModelManifestValidationError.invalidManifest
            }
            expectedDigests[fileName] = String(fields[0]).lowercased()
        }

        guard expectedDigests.count == requiredFileNames.count else {
            throw ModelManifestValidationError.invalidManifest
        }
        for fileName in requiredFileNames where expectedDigests[fileName] != (try checksum(
            of: directory.appendingPathComponent(fileName)
        )) {
            throw ModelManifestValidationError.checksumMismatch(fileName)
        }
    }

    private static func checksum(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
