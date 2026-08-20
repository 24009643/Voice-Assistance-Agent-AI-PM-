import Foundation

enum TranscriptStoreError: Error, Equatable {
    case invalidSessionPath
}

final class TranscriptStore {
    static let defaultDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TSB/Sessions", isDirectory: true)

    private let directory: URL
    private(set) var skippedRecordCount = 0

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

    // ponytail: linear local scan is enough for 0.2; add an index only after measured latency or relevance failure.
    func list() throws -> [TranscriptRecord] {
        let fileManager = FileManager.default
        let root = directory.standardizedFileURL
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw TranscriptStoreError.invalidSessionPath
        }

        let entries = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        var canonicalIDs = Set<SessionID>()
        var records: [TranscriptRecord] = []

        for entry in entries {
            guard let rawID = UUID(uuidString: entry.lastPathComponent) else { continue }
            let id = SessionID(rawValue: rawID)
            guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true else { continue }
            canonicalIDs.insert(id)
            guard values.isSymbolicLink != true else {
                reportSkippedRecord()
                continue
            }

            let recordURL = entry.appendingPathComponent("record.json")
            guard fileManager.fileExists(atPath: recordURL.path) else {
                reportSkippedRecord()
                continue
            }
            guard let recordValues = try? recordURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  recordValues.isRegularFile == true,
                  recordValues.isSymbolicLink != true else {
                reportSkippedRecord()
                continue
            }
            do {
                let record = try decodeRecord(at: recordURL)
                guard record.id == id else {
                    reportSkippedRecord()
                    continue
                }
                records.append(record)
            } catch {
                reportSkippedRecord()
            }
        }

        for entry in entries {
            guard entry.pathExtension == "json",
                  let rawID = UUID(uuidString: entry.deletingPathExtension().lastPathComponent),
                  let values = try? entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { continue }
            let id = SessionID(rawValue: rawID)
            guard !canonicalIDs.contains(id) else { continue }
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                reportSkippedRecord()
                continue
            }
            do {
                let record = try decodeRecord(at: entry)
                guard record.id == id else {
                    reportSkippedRecord()
                    continue
                }
                records.append(record)
            } catch {
                reportSkippedRecord()
            }
        }

        return records.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            if $0.ordinal != $1.ordinal { return $0.ordinal > $1.ordinal }
            return $0.id.rawValue.uuidString > $1.id.rawValue.uuidString
        }
    }

    func updateDeliveryStatus(id: SessionID, to status: DeliveryStatus) throws {
        try update(id: id) { $0.deliveryStatus = status }
    }

    func updateOrganization(id: SessionID, to organization: OrganizationRecord) throws {
        try update(id: id) { $0.organization = organization }
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

    private func update(id: SessionID, apply: (inout TranscriptRecord) -> Void) throws {
        let recordURL = existingRecordURL(for: id)
        var record = try decodeRecord(at: recordURL)
        apply(&record)
        try encodedData(for: record).write(to: recordURL, options: .atomic)
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

    private func reportSkippedRecord() {
        skippedRecordCount += 1
        NSLog("TSB: skipped malformed or unsafe transcript record")
    }
}
