import Foundation

struct DebugAudioFinalizer {
    private let shouldArchive: Bool
    private let archiveDirectory: URL

    init(isDebugBuild: Bool, environment: [String: String], archiveDirectory: URL) {
        shouldArchive = isDebugBuild && environment["TSB_RETAIN_DEBUG_AUDIO"] == "1"
        self.archiveDirectory = archiveDirectory
    }

    func finalize(_ source: URL, sessionID: SessionID) throws {
        guard shouldArchive else {
            try FileManager.default.removeItem(at: source)
            return
        }

        try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        let destination = archiveDirectory.appendingPathComponent("\(sessionID.rawValue.uuidString).wav")
        try FileManager.default.moveItem(at: source, to: destination)
    }
}
