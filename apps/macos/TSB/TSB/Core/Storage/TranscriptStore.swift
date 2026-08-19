import Foundation

final class TranscriptStore {
    static let defaultDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TSB/Sessions", isDirectory: true)

    private let directory: URL

    init(directory: URL = TranscriptStore.defaultDirectory) {
        self.directory = directory
    }

    func save(_ record: TranscriptRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encodedData(for: record).write(to: fileURL(for: record.id), options: .atomic)
    }

    func load(id: SessionID) throws -> TranscriptRecord {
        try JSONDecoder().decode(TranscriptRecord.self, from: Data(contentsOf: fileURL(for: id)))
    }

    func updateDeliveryStatus(id: SessionID, to status: DeliveryStatus) throws {
        let record = try load(id: id)
        try save(
            TranscriptRecord(
                id: record.id,
                ordinal: record.ordinal,
                createdAt: record.createdAt,
                durationMilliseconds: record.durationMilliseconds,
                detectedLanguages: record.detectedLanguages,
                originalText: record.originalText,
                localCleanedText: record.localCleanedText,
                edits: record.edits,
                deliveryStatus: status
            )
        )
    }

    private func encodedData(for record: TranscriptRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(record)
    }

    private func fileURL(for id: SessionID) -> URL {
        directory.appendingPathComponent(id.rawValue.uuidString).appendingPathExtension("json")
    }
}
