#if DEBUG
import AppKit
import AVFoundation
import Combine
import Foundation

struct V02AcceptanceConfiguration: Equatable {
    let wavURL: URL
    let outputURL: URL
    let cycles: Int

    static func parse(
        environment: [String: String],
        isRegularFile: (URL) -> Bool = { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    ) -> Self? {
        guard environment["TSB_V02_ACCEPTANCE_RUN"] == "1",
              let wavPath = environment["TSB_V02_ACCEPTANCE_WAV"], !wavPath.isEmpty,
              let outputPath = environment["TSB_V02_ACCEPTANCE_OUTPUT"], !outputPath.isEmpty,
              let rawCycles = environment["TSB_V02_ACCEPTANCE_CYCLES"],
              let cycles = Int(rawCycles), cycles > 0 else { return nil }
        let wavURL = URL(fileURLWithPath: wavPath)
        let outputURL = URL(fileURLWithPath: outputPath)
        guard wavURL.pathExtension.lowercased() == "wav",
              outputURL.pathExtension.lowercased() == "jsonl",
              wavURL.standardizedFileURL != outputURL.standardizedFileURL,
              isRegularFile(wavURL) else { return nil }
        return Self(wavURL: wavURL, outputURL: outputURL, cycles: cycles)
    }
}

struct V02AcceptanceCycleEvidence: Encodable {
    let cycleNumber: Int
    let sessionID: UUID?
    let firstPreviewMilliseconds: Int?
    let stopToLocalFinalMilliseconds: Int?
    let stopToCopyMilliseconds: Int?
    let deliveryStatus: String
    let recordDelta: Int?
    let copyChangeCountDelta: Int?
    let organizationTerminalCategory: String
    let immediateEqualsLocal: Bool
    let postOrganizationEqualsLocal: Bool
    let organizationDidNotRecopy: Bool
    let resultCategory: String

    private enum CodingKeys: String, CodingKey {
        case rowType = "row_type"
        case cycleNumber = "cycle_number"
        case sessionID = "session_id"
        case firstPreviewMilliseconds = "first_preview_milliseconds"
        case stopToLocalFinalMilliseconds = "stop_to_local_final_milliseconds"
        case stopToCopyMilliseconds = "stop_to_copy_milliseconds"
        case deliveryStatus = "delivery_status"
        case recordDelta = "record_delta"
        case copyChangeCountDelta = "copy_change_count_delta"
        case organizationTerminalCategory = "organization_terminal_category"
        case immediateEqualsLocal = "immediate_equals_local"
        case postOrganizationEqualsLocal = "post_organization_equals_local"
        case organizationDidNotRecopy = "organization_did_not_recopy"
        case resultCategory = "result_category"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("cycle", forKey: .rowType)
        try container.encode(cycleNumber, forKey: .cycleNumber)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(firstPreviewMilliseconds, forKey: .firstPreviewMilliseconds)
        try container.encode(stopToLocalFinalMilliseconds, forKey: .stopToLocalFinalMilliseconds)
        try container.encode(stopToCopyMilliseconds, forKey: .stopToCopyMilliseconds)
        try container.encode(deliveryStatus, forKey: .deliveryStatus)
        try container.encode(recordDelta, forKey: .recordDelta)
        try container.encode(copyChangeCountDelta, forKey: .copyChangeCountDelta)
        try container.encode(organizationTerminalCategory, forKey: .organizationTerminalCategory)
        try container.encode(immediateEqualsLocal, forKey: .immediateEqualsLocal)
        try container.encode(postOrganizationEqualsLocal, forKey: .postOrganizationEqualsLocal)
        try container.encode(organizationDidNotRecopy, forKey: .organizationDidNotRecopy)
        try container.encode(resultCategory, forKey: .resultCategory)
    }
}

struct V02AcceptanceSummaryEvidence: Encodable {
    let requestedCycles: Int
    let completedCycles: Int
    let uniqueSessionIDCount: Int
    let firstPreviewP95Milliseconds: Int
    let firstPreviewMaximumMilliseconds: Int
    let stopToLocalFinalP95Milliseconds: Int
    let stopToLocalFinalMaximumMilliseconds: Int
    let stopToCopyP95Milliseconds: Int
    let stopToCopyMaximumMilliseconds: Int
    let lostRecordCount: Int
    let duplicateCopyCount: Int
    let organizationRecopyCount: Int
    let m10Eligible: Bool
    let m10Passed: Bool
    let resultCategory: String

    private enum CodingKeys: String, CodingKey {
        case rowType = "row_type"
        case requestedCycles = "requested_cycles"
        case completedCycles = "completed_cycles"
        case uniqueSessionIDCount = "unique_session_id_count"
        case firstPreviewP95Milliseconds = "first_preview_p95_milliseconds"
        case firstPreviewMaximumMilliseconds = "first_preview_maximum_milliseconds"
        case stopToLocalFinalP95Milliseconds = "stop_to_local_final_p95_milliseconds"
        case stopToLocalFinalMaximumMilliseconds = "stop_to_local_final_maximum_milliseconds"
        case stopToCopyP95Milliseconds = "stop_to_copy_p95_milliseconds"
        case stopToCopyMaximumMilliseconds = "stop_to_copy_maximum_milliseconds"
        case lostRecordCount = "lost_record_count"
        case duplicateCopyCount = "duplicate_copy_count"
        case organizationRecopyCount = "organization_recopy_count"
        case m10Eligible = "m10_eligible"
        case m10Passed = "m10_passed"
        case resultCategory = "result_category"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("summary", forKey: .rowType)
        try container.encode(requestedCycles, forKey: .requestedCycles)
        try container.encode(completedCycles, forKey: .completedCycles)
        try container.encode(uniqueSessionIDCount, forKey: .uniqueSessionIDCount)
        try container.encode(firstPreviewP95Milliseconds, forKey: .firstPreviewP95Milliseconds)
        try container.encode(firstPreviewMaximumMilliseconds, forKey: .firstPreviewMaximumMilliseconds)
        try container.encode(stopToLocalFinalP95Milliseconds, forKey: .stopToLocalFinalP95Milliseconds)
        try container.encode(stopToLocalFinalMaximumMilliseconds, forKey: .stopToLocalFinalMaximumMilliseconds)
        try container.encode(stopToCopyP95Milliseconds, forKey: .stopToCopyP95Milliseconds)
        try container.encode(stopToCopyMaximumMilliseconds, forKey: .stopToCopyMaximumMilliseconds)
        try container.encode(lostRecordCount, forKey: .lostRecordCount)
        try container.encode(duplicateCopyCount, forKey: .duplicateCopyCount)
        try container.encode(organizationRecopyCount, forKey: .organizationRecopyCount)
        try container.encode(m10Eligible, forKey: .m10Eligible)
        try container.encode(m10Passed, forKey: .m10Passed)
        try container.encode(resultCategory, forKey: .resultCategory)
    }
}

enum V02AcceptanceMetrics {
    static func percentile95<S: Sequence>(_ samples: S) -> Int? where S.Element == Int {
        let sorted = samples.sorted()
        guard !sorted.isEmpty else { return nil }
        let index = Int(ceil(0.95 * Double(sorted.count))) - 1
        return sorted[index]
    }

    static func summarize(
        cycles: [V02AcceptanceCycleEvidence],
        requestedCycles: Int
    ) -> V02AcceptanceSummaryEvidence {
        let firstPreview = cycles.compactMap(\.firstPreviewMilliseconds)
        let stopToLocalFinal = cycles.compactMap(\.stopToLocalFinalMilliseconds)
        let stopToCopy = cycles.compactMap(\.stopToCopyMilliseconds)
        let lostRecords = cycles.filter { $0.recordDelta != 1 }.count
        let duplicateCopies = cycles.filter { ($0.copyChangeCountDelta ?? 0) > 1 }.count
        let organizationRecopies = cycles.filter { !$0.organizationDidNotRecopy }.count
        let uniqueSessionIDs = Set(cycles.compactMap(\.sessionID)).count
        let eligible = requestedCycles == 100 && cycles.count == 100
        let passed = eligible
            && firstPreview.count == 100
            && stopToLocalFinal.count == 100
            && stopToCopy.count == 100
            && (percentile95(firstPreview) ?? .max) <= 800
            && (percentile95(stopToLocalFinal) ?? .max) <= 1_500
            && (percentile95(stopToCopy) ?? .max) <= 2_000
            && (stopToCopy.max() ?? .max) <= 3_000
            && lostRecords == 0
            && duplicateCopies == 0
            && organizationRecopies == 0
            && uniqueSessionIDs == 100
            && cycles.allSatisfy { $0.resultCategory == "passed" }
        return V02AcceptanceSummaryEvidence(
            requestedCycles: requestedCycles,
            completedCycles: cycles.count,
            uniqueSessionIDCount: uniqueSessionIDs,
            firstPreviewP95Milliseconds: percentile95(firstPreview) ?? 0,
            firstPreviewMaximumMilliseconds: firstPreview.max() ?? 0,
            stopToLocalFinalP95Milliseconds: percentile95(stopToLocalFinal) ?? 0,
            stopToLocalFinalMaximumMilliseconds: stopToLocalFinal.max() ?? 0,
            stopToCopyP95Milliseconds: percentile95(stopToCopy) ?? 0,
            stopToCopyMaximumMilliseconds: stopToCopy.max() ?? 0,
            lostRecordCount: lostRecords,
            duplicateCopyCount: duplicateCopies,
            organizationRecopyCount: organizationRecopies,
            m10Eligible: eligible,
            m10Passed: passed,
            resultCategory: !eligible ? "m10_ineligible" : passed ? "m10_passed" : "m10_failed"
        )
    }
}

@MainActor
final class V02AcceptanceRunner {
    private struct Capture {
        let cycleNumber: Int
        let initialRecordCount: Int
        let initialPasteboardChangeCount: Int
        var sessionID: SessionID?
        var recordingInstant: ContinuousClock.Instant?
        var firstPreviewInstant: ContinuousClock.Instant?
        var stopInstant: ContinuousClock.Instant?
        var localFinalInstant: ContinuousClock.Instant?
        var deliveredInstant: ContinuousClock.Instant?
        var deliveredPasteboardChangeCount: Int?
        var terminalPasteboardChangeCount: Int?
        var deliveryStatus = "missing"
        var recordDelta: Int?
        var copyChangeCountDelta: Int?
        var terminalCategory = "missing"
        var immediateEqualsLocal = false
        var postOrganizationEqualsLocal = false
        var organizationDidNotRecopy = false
        var failureCategory: String?
        var deliveredLocalText: String?
    }

    private let configuration: V02AcceptanceConfiguration
    private let controller: AppController
    private let store: TranscriptStore
    private let pasteboard: NSPasteboard
    private let clock = ContinuousClock()
    private var capture: Capture?
    private var observation: AnyCancellable?

    static func startIfConfigured(
        controller: AppController,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard let configuration = V02AcceptanceConfiguration.parse(environment: environment) else { return }
        let runner = V02AcceptanceRunner(configuration: configuration, controller: controller)
        Task { @MainActor in
            await runner.run()
        }
    }

    init(
        configuration: V02AcceptanceConfiguration,
        controller: AppController,
        store: TranscriptStore = TranscriptStore(),
        pasteboard: NSPasteboard = .general
    ) {
        self.configuration = configuration
        self.controller = controller
        self.store = store
        self.pasteboard = pasteboard
    }

    private func run() async {
        guard let writer = try? V02JSONLWriter(url: configuration.outputURL) else { return }
        observation = controller.state.$snapshot.sink { @MainActor [weak self] snapshot in
            self?.observe(snapshot)
        }
        var rows: [V02AcceptanceCycleEvidence] = []
        for cycleNumber in 1...configuration.cycles {
            let row = await runCycle(cycleNumber)
            do {
                try writer.append(row)
            } catch {
                return
            }
            rows.append(row)
            if row.resultCategory != "passed" { break }
        }
        try? writer.append(V02AcceptanceMetrics.summarize(
            cycles: rows,
            requestedCycles: configuration.cycles
        ))
    }

    private func runCycle(_ cycleNumber: Int) async -> V02AcceptanceCycleEvidence {
        let initialRecordCount: Int
        do {
            initialRecordCount = try store.list().count
        } catch {
            capture = Capture(
                cycleNumber: cycleNumber,
                initialRecordCount: 0,
                initialPasteboardChangeCount: pasteboard.changeCount,
                failureCategory: "record_scan_failed"
            )
            return evidence()
        }
        capture = Capture(
            cycleNumber: cycleNumber,
            initialRecordCount: initialRecordCount,
            initialPasteboardChangeCount: pasteboard.changeCount
        )

        controller.toggleForDevelopment()
        guard await wait(until: { self.capture?.sessionID != nil || self.capture?.failureCategory != nil }, seconds: 10),
              capture?.sessionID != nil else {
            failIfNeeded("recording_start_timeout")
            return evidence()
        }

        guard let player = try? AVAudioPlayer(contentsOf: configuration.wavURL), player.play() else {
            capture?.failureCategory = "playback_failed"
            stopRecordingIfNeeded()
            return evidence()
        }
        let playbackTimeout = Int64(min(max(ceil(player.duration) + 5, 10), 300))
        guard await wait(until: { !player.isPlaying }, seconds: playbackTimeout) else {
            player.stop()
            capture?.failureCategory = "playback_timeout"
            stopRecordingIfNeeded()
            return evidence()
        }
        guard capture?.firstPreviewInstant != nil else {
            capture?.failureCategory = "preview_missing"
            stopRecordingIfNeeded()
            return evidence()
        }

        capture?.stopInstant = clock.now
        controller.toggleForDevelopment()
        guard await wait(until: { self.capture?.localFinalInstant != nil || self.capture?.failureCategory != nil }, seconds: 30),
              capture?.localFinalInstant != nil else {
            failIfNeeded("local_final_timeout")
            return evidence()
        }
        guard await wait(until: { self.capture?.deliveredInstant != nil || self.capture?.failureCategory != nil }, seconds: 30),
              capture?.deliveredInstant != nil else {
            failIfNeeded("delivery_timeout")
            return evidence()
        }
        guard await wait(until: { self.capture?.terminalCategory != "missing" || self.capture?.failureCategory != nil }, seconds: 30),
              capture?.terminalCategory != "missing" else {
            failIfNeeded("organization_timeout")
            return evidence()
        }

        if capture?.recordDelta != 1 || capture?.deliveryStatus != DeliveryStatus.copied.rawValue {
            capture?.failureCategory = "lost_record"
        } else if capture?.copyChangeCountDelta != 1 {
            capture?.failureCategory = "copy_delta_invalid"
        } else if capture?.immediateEqualsLocal != true {
            capture?.failureCategory = "clipboard_not_local"
        } else if capture?.terminalCategory.hasPrefix("organized_") != true {
            capture?.failureCategory = "organization_not_successful"
        } else if capture?.organizationDidNotRecopy != true {
            capture?.failureCategory = "organization_recopy"
        } else if capture?.postOrganizationEqualsLocal != true {
            capture?.failureCategory = "clipboard_changed"
        }
        return evidence()
    }

    private func observe(_ snapshot: AppSnapshot) {
        guard capture != nil else { return }
        let now = clock.now
        if capture?.sessionID == nil {
            if snapshot.status == .recording, let sessionID = snapshot.sessionID {
                capture?.sessionID = sessionID
                capture?.recordingInstant = now
            } else if snapshot.status == .failed {
                capture?.failureCategory = "recording_start_failed"
            }
            return
        }
        guard snapshot.sessionID == capture?.sessionID else {
            if snapshot.sessionID != nil { failIfNeeded("session_mismatch") }
            return
        }

        if capture?.firstPreviewInstant == nil,
           snapshot.status == .recording,
           !snapshot.previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            capture?.firstPreviewInstant = now
        }
        if capture?.stopInstant != nil,
           capture?.localFinalInstant == nil,
           snapshot.status == .saving {
            capture?.localFinalInstant = now
        }
        if capture?.deliveredInstant == nil, snapshot.status == .delivered {
            captureDelivered(snapshot, at: now)
        }
        if capture?.deliveredInstant != nil,
           capture?.terminalCategory == "missing",
           let category = Self.terminalCategory(for: snapshot.organizationPhase) {
            capture?.terminalCategory = category
            let changeCount = pasteboard.changeCount
            let deliveredLocalText = capture?.deliveredLocalText
            let deliveredChangeCount = capture?.deliveredPasteboardChangeCount
            capture?.terminalPasteboardChangeCount = changeCount
            capture?.postOrganizationEqualsLocal = pasteboard.string(forType: .string) == deliveredLocalText
            capture?.organizationDidNotRecopy = changeCount == deliveredChangeCount
        }
        if capture?.stopInstant != nil,
           capture?.deliveredInstant == nil,
           snapshot.status == .failed || snapshot.status == .cancelled {
            capture?.failureCategory = "local_delivery_failed"
        }
    }

    private func captureDelivered(_ snapshot: AppSnapshot, at instant: ContinuousClock.Instant) {
        guard let sessionID = capture?.sessionID else { return }
        capture?.deliveredInstant = instant
        capture?.deliveredLocalText = snapshot.previewText
        let changeCount = pasteboard.changeCount
        let initialChangeCount = capture?.initialPasteboardChangeCount ?? changeCount
        capture?.deliveredPasteboardChangeCount = changeCount
        capture?.copyChangeCountDelta = changeCount - initialChangeCount
        capture?.immediateEqualsLocal = pasteboard.string(forType: .string) == snapshot.previewText
        do {
            let record = try store.load(id: sessionID)
            let initialRecordCount = capture?.initialRecordCount ?? 0
            capture?.deliveryStatus = record.deliveryStatus.rawValue
            capture?.recordDelta = try store.list().count - initialRecordCount
        } catch {
            capture?.failureCategory = "record_lookup_failed"
        }
    }

    private func evidence() -> V02AcceptanceCycleEvidence {
        guard let capture else {
            return V02AcceptanceCycleEvidence(
                cycleNumber: 0,
                sessionID: nil,
                firstPreviewMilliseconds: nil,
                stopToLocalFinalMilliseconds: nil,
                stopToCopyMilliseconds: nil,
                deliveryStatus: "missing",
                recordDelta: nil,
                copyChangeCountDelta: nil,
                organizationTerminalCategory: "missing",
                immediateEqualsLocal: false,
                postOrganizationEqualsLocal: false,
                organizationDidNotRecopy: false,
                resultCategory: "runner_state_missing"
            )
        }
        return V02AcceptanceCycleEvidence(
            cycleNumber: capture.cycleNumber,
            sessionID: capture.sessionID?.rawValue,
            firstPreviewMilliseconds: milliseconds(from: capture.recordingInstant, to: capture.firstPreviewInstant),
            stopToLocalFinalMilliseconds: milliseconds(from: capture.stopInstant, to: capture.localFinalInstant),
            stopToCopyMilliseconds: milliseconds(from: capture.stopInstant, to: capture.deliveredInstant),
            deliveryStatus: capture.deliveryStatus,
            recordDelta: capture.recordDelta,
            copyChangeCountDelta: capture.copyChangeCountDelta,
            organizationTerminalCategory: capture.terminalCategory,
            immediateEqualsLocal: capture.immediateEqualsLocal,
            postOrganizationEqualsLocal: capture.postOrganizationEqualsLocal,
            organizationDidNotRecopy: capture.organizationDidNotRecopy,
            resultCategory: capture.failureCategory ?? "passed"
        )
    }

    private func wait(
        until condition: @escaping @MainActor () -> Bool,
        seconds: Int64
    ) async -> Bool {
        let deadline = clock.now.advanced(by: .seconds(seconds))
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func failIfNeeded(_ category: String) {
        guard capture?.failureCategory == nil else { return }
        capture?.failureCategory = category
    }

    private func stopRecordingIfNeeded() {
        guard let sessionID = capture?.sessionID,
              controller.state.snapshot.sessionID == sessionID,
              controller.state.snapshot.status == .recording else { return }
        capture?.stopInstant = clock.now
        controller.toggleForDevelopment()
    }

    private func milliseconds(
        from start: ContinuousClock.Instant?,
        to end: ContinuousClock.Instant?
    ) -> Int? {
        guard let start, let end else { return nil }
        let components = start.duration(to: end).components
        return Int(components.seconds) * 1_000 + Int(components.attoseconds / 1_000_000_000_000_000)
    }

    private static func terminalCategory(for phase: OrganizationPhase) -> String? {
        switch phase {
        case let .organized(record):
            return record.providerKind == .local ? "organized_local" : "organized_remote"
        case .authorizationRequired:
            return "authorization_required"
        case .failed:
            return "failed"
        case .notRequested, .localOnly, .queued, .organizing:
            return nil
        }
    }
}

private final class V02JSONLWriter {
    private let handle: FileHandle
    private let encoder = JSONEncoder()

    init(url: URL) throws {
        encoder.outputFormatting = [.sortedKeys]
        try Data().write(to: url, options: .atomic)
        handle = try FileHandle(forWritingTo: url)
    }

    func append<T: Encodable>(_ row: T) throws {
        var data = try encoder.encode(row)
        data.append(0x0A)
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    deinit {
        try? handle.close()
    }
}
#endif
