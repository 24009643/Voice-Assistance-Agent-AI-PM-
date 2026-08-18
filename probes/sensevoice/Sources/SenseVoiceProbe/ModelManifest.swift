import Foundation

public struct ModelManifest: Sendable {
    public let samples: [Sample]

    public struct Sample: Codable, Equatable, Sendable {
        public let id: String
        public let path: String
        public let language: String
        public let durationSeconds: Double?

        enum CodingKeys: String, CodingKey {
            case id
            case path
            case language
            case durationSeconds = "duration_seconds"
        }
    }

    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case malformedLine(Int, String)
        case emptyID(line: Int)
        case duplicateID(String)
        case missingLanguage(id: String)
        case missingFile(id: String, path: String)
        case nonWavFile(id: String, path: String)

        public var description: String {
            switch self {
            case let .malformedLine(line, reason):
                return "manifest line \(line) is invalid JSON: \(reason)"
            case let .emptyID(line):
                return "manifest line \(line) has an empty id"
            case let .duplicateID(id):
                return "manifest contains duplicate id '\(id)'"
            case let .missingLanguage(id):
                return "manifest sample '\(id)' has an empty language label"
            case let .missingFile(id, path):
                return "manifest sample '\(id)' points to a missing file: \(path)"
            case let .nonWavFile(id, path):
                return "manifest sample '\(id)' is not a WAV file: \(path)"
            }
        }
    }

    public static func load(from url: URL) throws -> ModelManifest {
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        var samples: [Sample] = []
        var seenIDs = Set<String>()

        for (offset, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let sample: Sample
            do {
                sample = try decoder.decode(Sample.self, from: Data(line.utf8))
            } catch {
                throw ValidationError.malformedLine(offset + 1, String(describing: error))
            }

            guard !sample.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.emptyID(line: offset + 1)
            }
            guard seenIDs.insert(sample.id).inserted else {
                throw ValidationError.duplicateID(sample.id)
            }
            guard !sample.language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.missingLanguage(id: sample.id)
            }
            guard FileManager.default.fileExists(atPath: sample.path) else {
                throw ValidationError.missingFile(id: sample.id, path: sample.path)
            }
            guard URL(fileURLWithPath: sample.path).pathExtension.lowercased() == "wav" else {
                throw ValidationError.nonWavFile(id: sample.id, path: sample.path)
            }

            samples.append(sample)
        }

        return ModelManifest(samples: samples)
    }
}
