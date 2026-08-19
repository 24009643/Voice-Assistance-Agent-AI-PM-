import Foundation

enum TranscriptStoreError: Error, Equatable {
    case invalidSessionPath
}

final class TranscriptStore {
    static let defaultDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TSB/Sessions", isDirectory: true)

    private let directory: URL

    init(directory: URL = TranscriptStore.defaultDirectory) {
        self.directory = directory
    }

    func save(_ record: TranscriptRecord) throws {
        let recordURL = canonicalRecordURL(for: record.id)
        try FileManager.default.createDirectory(at: recordURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encodedData(for: record).write(to: recordURL, options: .atomic)
    }

    func load(id: SessionID) throws -> TranscriptRecord {
        try decodeRecord(at: existingRecordURL(for: id))
    }

    func updateDeliveryStatus(id: SessionID, to status: DeliveryStatus) throws {
        let recordURL = existingRecordURL(for: id)
        var record = try decodeRecord(at: recordURL)
        record.deliveryStatus = status
        try encodedData(for: record).write(to: recordURL, options: .atomic)
    }

    func removeSession(id: SessionID) throws {
        let sessionURL = sessionDirectoryURL(for: id)
        guard sessionURL.deletingLastPathComponent() == directory.standardizedFileURL else {
            throw TranscriptStoreError.invalidSessionPath
        }
        guard FileManager.default.fileExists(atPath: sessionURL.path) else { return }

        let values = try sessionURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw TranscriptStoreError.invalidSessionPath
        }
        try FileManager.default.removeItem(at: sessionURL)
    }

    private func encodedData(for record: TranscriptRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(record)
    }

    private func decodeRecord(at url: URL) throws -> TranscriptRecord {
        try JSONDecoder().decode(TranscriptRecord.self, from: Data(contentsOf: url))
    }

    private func existingRecordURL(for id: SessionID) -> URL {
        let canonicalURL = canonicalRecordURL(for: id)
        return FileManager.default.fileExists(atPath: canonicalURL.path) ? canonicalURL : legacyRecordURL(for: id)
    }

    private func canonicalRecordURL(for id: SessionID) -> URL {
        sessionDirectoryURL(for: id).appendingPathComponent("record.json")
    }

    private func legacyRecordURL(for id: SessionID) -> URL {
        directory.appendingPathComponent(id.rawValue.uuidString).appendingPathExtension("json")
    }

    private func sessionDirectoryURL(for id: SessionID) -> URL {
        directory.standardizedFileURL.appendingPathComponent(id.rawValue.uuidString, isDirectory: true)
    }
}
