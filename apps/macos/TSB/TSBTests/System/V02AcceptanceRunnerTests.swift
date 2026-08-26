import AppKit
import AVFoundation
import CryptoKit
import Foundation
import XCTest
@testable import TSB

@MainActor
final class V02AcceptanceRunnerTests: XCTestCase {
    func testLocalFinalExistsOnlyAfterTheExactRecordIsDurablyReadable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V02AcceptanceRunnerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptStore(directory: directory)
        let sessionID = SessionID(rawValue: UUID())

        XCTAssertFalse(V02AcceptanceRunner.hasDurableLocalFinal(sessionID: sessionID, store: store))

        try store.save(TranscriptRecord(
            id: sessionID,
            ordinal: SessionOrdinal(rawValue: 1),
            createdAt: Date(),
            durationMilliseconds: 1,
            detectedLanguages: ["zh"],
            originalText: "saved",
            localCleanedText: "saved",
            edits: [],
            deliveryStatus: .pending
        ))

        XCTAssertTrue(V02AcceptanceRunner.hasDurableLocalFinal(sessionID: sessionID, store: store))
    }

    func testConfigurationRequiresExactOptInAndEveryValidInputWithoutCreatingAnything() {
        let validEnvironment = [
            "TSB_V02_ACCEPTANCE_RUN": "1",
            "TSB_V02_ACCEPTANCE_WAV": "/synthetic/input.wav",
            "TSB_V02_ACCEPTANCE_OUTPUT": "/synthetic/evidence.jsonl",
            "TSB_V02_ACCEPTANCE_CYCLES": "3"
        ]
        var fileChecks = 0
        let isRegularFile: (URL) -> Bool = { _ in
            fileChecks += 1
            return true
        }

        XCTAssertTrue(V02AcceptanceConfiguration.parse(environment: [:], isRegularFile: isRegularFile) == nil)
        XCTAssertTrue(V02AcceptanceConfiguration.parse(
            environment: validEnvironment.merging(["TSB_V02_ACCEPTANCE_RUN": "true"]) { _, new in new },
            isRegularFile: isRegularFile
        ) == nil)
        XCTAssertTrue(V02AcceptanceConfiguration.parse(
            environment: validEnvironment.filter { $0.key != "TSB_V02_ACCEPTANCE_OUTPUT" },
            isRegularFile: isRegularFile
        ) == nil)
        XCTAssertTrue(V02AcceptanceConfiguration.parse(
            environment: validEnvironment.merging(["TSB_V02_ACCEPTANCE_CYCLES": "0"]) { _, new in new },
            isRegularFile: isRegularFile
        ) == nil)
        XCTAssertTrue(V02AcceptanceConfiguration.parse(
            environment: validEnvironment.merging(["TSB_V02_ACCEPTANCE_OUTPUT": "/synthetic/input.wav"]) { _, new in new },
            isRegularFile: isRegularFile
        ) == nil)
        XCTAssertEqual(fileChecks, 0)

        XCTAssertTrue(V02AcceptanceConfiguration.parse(environment: validEnvironment, isRegularFile: { _ in false }) == nil)
        let configuration = V02AcceptanceConfiguration.parse(
            environment: validEnvironment,
            isRegularFile: isRegularFile
        )

        XCTAssertEqual(configuration?.cycles, 3)
        XCTAssertEqual(fileChecks, 1)
    }

    func testConfigurationAcceptsOnlyCycleCountsOneThroughOneHundredBeforeFileChecks() {
        let invalidCounts = [
            "0",
            "-1",
            "101",
            String(Int.max),
            String(Int.max) + "0"
        ]

        for count in invalidCounts {
            var fileChecks = 0
            let configuration = V02AcceptanceConfiguration.parse(
                environment: [
                    "TSB_V02_ACCEPTANCE_RUN": "1",
                    "TSB_V02_ACCEPTANCE_WAV": "/synthetic/input.wav",
                    "TSB_V02_ACCEPTANCE_OUTPUT": "/synthetic/evidence.jsonl",
                    "TSB_V02_ACCEPTANCE_CYCLES": count
                ],
                isRegularFile: { _ in
                    fileChecks += 1
                    return true
                }
            )

            XCTAssertNil(configuration, "count: \(count)")
            XCTAssertEqual(fileChecks, 0, "count: \(count)")
        }

        for count in ["1", "100"] {
            let configuration = V02AcceptanceConfiguration.parse(
                environment: [
                    "TSB_V02_ACCEPTANCE_RUN": "1",
                    "TSB_V02_ACCEPTANCE_WAV": "/synthetic/input.wav",
                    "TSB_V02_ACCEPTANCE_OUTPUT": "/synthetic/evidence.jsonl",
                    "TSB_V02_ACCEPTANCE_CYCLES": count
                ],
                isRegularFile: { _ in true }
            )

            XCTAssertEqual(configuration?.cycles, Int(count))
        }
    }

    func testAuthorizedRunnerStartsWithoutRequestingMicrophonePermission() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V02AcceptanceRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (environment, _) = try configuredRun(in: directory)
        let harness = RunnerFailureHarness(recordsDirectory: directory.appendingPathComponent("records"))
        var permissionRequests = 0

        V02AcceptanceRunner.startIfConfigured(
            controller: harness.controller,
            environment: environment,
            microphoneAuthorizationStatus: { .authorized },
            requestMicrophonePermission: { _ in permissionRequests += 1 }
        )
        await harness.waitUntilRecordingStarts()

        XCTAssertEqual(permissionRequests, 0)
        XCTAssertEqual(harness.startCount, 1)
    }

    func testNotDeterminedRequestsOnceAndStartsAfterGrant() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V02AcceptanceRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (environment, _) = try configuredRun(in: directory)
        let harness = RunnerFailureHarness(recordsDirectory: directory.appendingPathComponent("records"))
        var permissionRequests = 0

        V02AcceptanceRunner.startIfConfigured(
            controller: harness.controller,
            environment: environment,
            microphoneAuthorizationStatus: { .notDetermined },
            requestMicrophonePermission: { completion in
                permissionRequests += 1
                completion(true)
            }
        )
        await harness.waitUntilRecordingStarts()

        XCTAssertEqual(permissionRequests, 1)
        XCTAssertEqual(harness.startCount, 1)
    }

    func testNotDeterminedDenialWritesOnlyOneSetupFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V02AcceptanceRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (environment, outputURL) = try configuredRun(in: directory)
        let harness = RunnerFailureHarness(recordsDirectory: directory.appendingPathComponent("records"))
        var permissionRequests = 0

        V02AcceptanceRunner.startIfConfigured(
            controller: harness.controller,
            environment: environment,
            microphoneAuthorizationStatus: { .notDetermined },
            requestMicrophonePermission: { completion in
                permissionRequests += 1
                completion(false)
            }
        )
        await harness.drainCallbacks()

        XCTAssertEqual(permissionRequests, 1)
        try assertSinglePermissionSetupFailure(at: outputURL)
        try assertNoAcceptanceRuntimeSideEffects(harness)
    }

    func testDeniedAndRestrictedWriteSetupFailureWithoutRequestingPermission() async throws {
        for status in [AVAuthorizationStatus.denied, .restricted] {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("V02AcceptanceRunnerTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            let (environment, outputURL) = try configuredRun(in: directory)
            let harness = RunnerFailureHarness(recordsDirectory: directory.appendingPathComponent("records"))
            var permissionRequests = 0

            V02AcceptanceRunner.startIfConfigured(
                controller: harness.controller,
                environment: environment,
                microphoneAuthorizationStatus: { status },
                requestMicrophonePermission: { _ in permissionRequests += 1 }
            )
            await harness.drainCallbacks()

            XCTAssertEqual(permissionRequests, 0, "status: \(status.rawValue)")
            try assertSinglePermissionSetupFailure(at: outputURL)
            try assertNoAcceptanceRuntimeSideEffects(harness)
        }
    }

    func testRunnerWithUnavailableParaformerModelStopsBeforeEvidenceAndRecording() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V02AcceptanceRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let wavURL = directory.appendingPathComponent("input.wav")
        let outputURL = directory.appendingPathComponent("evidence.jsonl")
        try Data().write(to: wavURL)
        let harness = RunnerFailureHarness(recordsDirectory: directory.appendingPathComponent("records"))
        var permissionChecks = 0
        var permissionRequests = 0

        V02AcceptanceRunner.startIfConfigured(
            controller: harness.controller,
            environment: [
                "TSB_V02_ACCEPTANCE_RUN": "1",
                "TSB_V02_ACCEPTANCE_WAV": wavURL.path,
                "TSB_V02_ACCEPTANCE_OUTPUT": outputURL.path,
                "TSB_V02_ACCEPTANCE_CYCLES": "1"
            ],
            microphoneAuthorizationStatus: {
                permissionChecks += 1
                return .notDetermined
            },
            requestMicrophonePermission: { _ in permissionRequests += 1 }
        )
        await harness.drainCallbacks()

        XCTAssertEqual(permissionChecks, 0)
        XCTAssertEqual(permissionRequests, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(harness.startCount, 0)
        XCTAssertEqual(harness.controller.state.snapshot.status, .idle)
        XCTAssertNil(harness.controller.state.snapshot.sessionID)
    }

    func testPlaybackFailureCancelsProductionSessionBeforeFailureRowAndRejectsLateFinishedAudio() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V02AcceptanceRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let wavURL = directory.appendingPathComponent("invalid.wav")
        let outputURL = directory.appendingPathComponent("evidence.jsonl")
        try Data().write(to: wavURL)
        let harness = RunnerFailureHarness(recordsDirectory: directory.appendingPathComponent("records"))
        let runner = V02AcceptanceRunner(
            configuration: V02AcceptanceConfiguration(wavURL: wavURL, outputURL: outputURL, cycles: 1),
            controller: harness.controller,
            store: harness.store,
            pasteboard: NSPasteboard(name: .init("V02AcceptanceRunnerTests.\(UUID().uuidString)"))
        )

        await runner.run()
        let rows = try String(contentsOf: outputURL, encoding: .utf8)
            .split(separator: "\n")
            .map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
        XCTAssertEqual(rows.first?["result_category"] as? String, "playback_failed")

        await harness.deliverLateFinishedAudio()

        XCTAssertEqual(harness.stopCount, 0)
        XCTAssertEqual(harness.cancelCount, 1)
        XCTAssertTrue(try harness.store.list().isEmpty)
        XCTAssertEqual(harness.copyCount, 0)
        XCTAssertEqual(harness.organizationDispatchCount, 0)
    }

    func testRunnerFailsClosedWhenDurableDeliveryExistsBeforeItsControlledStop() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V02AcceptanceRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let harness = RunnerFailureHarness(
            recordsDirectory: directory.appendingPathComponent("records")
        )
        let outputURL = directory.appendingPathComponent("evidence.jsonl")
        let runner = V02AcceptanceRunner(
            configuration: V02AcceptanceConfiguration(
                wavURL: directory.appendingPathComponent("unused.wav"),
                outputURL: outputURL,
                cycles: 1
            ),
            controller: harness.controller,
            store: harness.store,
            pasteboard: harness.pasteboard,
            playbackOverride: {
                harness.publishPreview("local preview")
                let sessionID = harness.state.snapshot.sessionID!
                try! harness.store.save(TranscriptRecord(
                    id: sessionID,
                    ordinal: SessionOrdinal(rawValue: 1),
                    createdAt: Date(),
                    durationMilliseconds: 1,
                    detectedLanguages: ["zh"],
                    originalText: "local final",
                    localCleanedText: "local final",
                    edits: [],
                    deliveryStatus: .copied,
                    deliveryReceipt: TranscriptDeliveryReceipt(
                        source: .local,
                        stopToLocalFinalMilliseconds: 1,
                        stopToCopyMilliseconds: 2
                    )
                ))
                return true
            }
        )

        await runner.run()
        let rows = try String(contentsOf: outputURL, encoding: .utf8)
            .split(separator: "\n")
            .map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }

        XCTAssertEqual(rows.first?["result_category"] as? String, "recording_ended_before_runner_stop")
        XCTAssertEqual(harness.stopCount, 0)
    }

    func testRunnerUsesExactDurableReceiptTimings() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V02AcceptanceRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let harness = RunnerFailureHarness(
            recordsDirectory: directory.appendingPathComponent("records"),
            finishesOnStop: true,
            deliveryReceiptOverride: TranscriptDeliveryReceipt(
                source: .local,
                stopToLocalFinalMilliseconds: 626,
                stopToCopyMilliseconds: 630
            )
        )
        let outputURL = directory.appendingPathComponent("evidence.jsonl")
        let runner = V02AcceptanceRunner(
            configuration: V02AcceptanceConfiguration(
                wavURL: directory.appendingPathComponent("unused.wav"),
                outputURL: outputURL,
                cycles: 1
            ),
            controller: harness.controller,
            store: harness.store,
            pasteboard: harness.pasteboard,
            playbackOverride: {
                harness.publishPreview("local preview")
                return true
            }
        )

        await runner.run()
        let rows = try String(contentsOf: outputURL, encoding: .utf8)
            .split(separator: "\n")
            .map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }

        XCTAssertEqual(rows.first?["stop_to_local_final_ms"] as? Int, 626)
        XCTAssertEqual(rows.first?["stop_to_copy_ms"] as? Int, 630)
        XCTAssertEqual(harness.stopCount, 1)
        XCTAssertEqual(rows.first?["result_category"] as? String, "passed")
    }

    func testFailureCleanupAfterIntentionalStopInvalidatesLateOrganizationResultWithoutRecopy() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V02AcceptanceRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let harness = RunnerFailureHarness(
            recordsDirectory: directory.appendingPathComponent("records"),
            suspendsOrganization: true
        )

        await harness.deliverOneSession()
        let sessionID = try XCTUnwrap(harness.state.snapshot.sessionID)
        let identity = try XCTUnwrap(harness.controller.developmentWorkIdentity(sessionID: sessionID))
        XCTAssertTrue(harness.controller.cancelDevelopmentWork(identity))
        harness.completeOrganization()
        await harness.drainCallbacks()

        XCTAssertEqual(harness.organizationDispatchCount, 1)
        XCTAssertEqual(harness.copyCount, 1)
        XCTAssertEqual(try harness.store.list().count, 1)
        XCTAssertEqual(try harness.store.load(id: sessionID).organization?.state, .failed)
        XCTAssertEqual(try harness.store.load(id: sessionID).organization?.errorCode, "cancelled")
    }

    func testQueuedStartCannotRunAfterRunnerWritesFailureEvidence() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V02AcceptanceRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let barrier = RunnerBarrier()
        let harness = RunnerFailureHarness(recordsDirectory: directory.appendingPathComponent("records"))
        harness.controller.enqueueBarrierForDevelopment { await barrier.wait() }
        let outputURL = directory.appendingPathComponent("evidence.jsonl")
        let runner = V02AcceptanceRunner(
            configuration: V02AcceptanceConfiguration(
                wavURL: directory.appendingPathComponent("unused.wav"),
                outputURL: outputURL,
                cycles: 1
            ),
            controller: harness.controller,
            store: harness.store,
            pasteboard: NSPasteboard(name: .init("V02AcceptanceRunnerTests.\(UUID().uuidString)")),
            recordingStartTimeoutSeconds: 0
        )

        await runner.run()
        let rows = try String(contentsOf: outputURL, encoding: .utf8)
            .split(separator: "\n")
            .map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
        XCTAssertEqual(rows.first?["result_category"] as? String, "playback_failed")
        barrier.release()
        await harness.drainCallbacks()

        XCTAssertNotEqual(harness.state.snapshot.status, .recording)
        XCTAssertTrue(try harness.store.list().isEmpty)
        XCTAssertEqual(harness.copyCount, 0)
        XCTAssertEqual(harness.organizationDispatchCount, 0)
    }

    func testOrganizationFailureEvidenceWaitsForOwnedCancellationInsensitiveTaskExit() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V02AcceptanceRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let harness = RunnerFailureHarness(
            recordsDirectory: directory.appendingPathComponent("records"),
            suspendsOrganization: true,
            finishesOnStop: true
        )
        let outputURL = directory.appendingPathComponent("evidence.jsonl")
        let runner = V02AcceptanceRunner(
            configuration: V02AcceptanceConfiguration(
                wavURL: directory.appendingPathComponent("unused.wav"),
                outputURL: outputURL,
                cycles: 1
            ),
            controller: harness.controller,
            store: harness.store,
            pasteboard: NSPasteboard(name: .init("V02AcceptanceRunnerTests.\(UUID().uuidString)")),
            organizationTimeoutSeconds: 0,
            playbackOverride: {
                harness.publishPreview("local preview")
                return true
            }
        )
        var runCompleted = false
        let task = Task { @MainActor in
            await runner.run()
            runCompleted = true
        }

        await harness.waitUntilOrganizationCancelled()
        await harness.drainCallbacks()
        let completedBeforeOwnedTaskExit = runCompleted
        harness.completeOrganization()
        await task.value
        let rows = try String(contentsOf: outputURL, encoding: .utf8)
            .split(separator: "\n")
            .map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }

        XCTAssertFalse(completedBeforeOwnedTaskExit)
        XCTAssertTrue(runCompleted)
        XCTAssertEqual(rows.first?["result_category"] as? String, "organization_timeout")
        XCTAssertEqual(harness.organizationDispatchCount, 1)
        XCTAssertEqual(harness.copyCount, 1)
    }

    func testCleanupTimeoutIsExplicitAndPreventsNextCycleWhilePreviewCancellationIsOwned() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V02AcceptanceRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let harness = RunnerFailureHarness(
            recordsDirectory: directory.appendingPathComponent("records"),
            suspendsPreviewCancellation: true
        )
        let outputURL = directory.appendingPathComponent("evidence.jsonl")
        let runner = V02AcceptanceRunner(
            configuration: V02AcceptanceConfiguration(
                wavURL: directory.appendingPathComponent("unused.wav"),
                outputURL: outputURL,
                cycles: 2
            ),
            controller: harness.controller,
            store: harness.store,
            pasteboard: NSPasteboard(name: .init("V02AcceptanceRunnerTests.\(UUID().uuidString)")),
            cleanupTimeoutSeconds: 0,
            playbackOverride: { false }
        )

        await runner.run()
        let rows = try String(contentsOf: outputURL, encoding: .utf8)
            .split(separator: "\n")
            .map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
        await harness.waitUntilPreviewCancellationStarts()

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first?["cycle_number"] as? Int, 1)
        XCTAssertEqual(rows.first?["result_category"] as? String, "failure_cleanup_timeout")
        XCTAssertEqual(harness.cancelCount, 1)
        XCTAssertTrue(try harness.store.list().isEmpty)
        XCTAssertEqual(harness.copyCount, 0)
        XCTAssertEqual(harness.organizationDispatchCount, 0)

        harness.completePreviewCancellation()
        await harness.drainCallbacks()
    }

    func testThrownRecordingStartTracksPreviewCleanupAndFailsClosedBeforeNextCycle() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V02AcceptanceRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let harness = RunnerFailureHarness(
            recordsDirectory: directory.appendingPathComponent("records"),
            suspendsPreviewCancellation: true,
            throwsOnRecordingStart: true
        )
        let outputURL = directory.appendingPathComponent("evidence.jsonl")
        let runner = V02AcceptanceRunner(
            configuration: V02AcceptanceConfiguration(
                wavURL: directory.appendingPathComponent("unused.wav"),
                outputURL: outputURL,
                cycles: 2
            ),
            controller: harness.controller,
            store: harness.store,
            pasteboard: NSPasteboard(name: .init("V02AcceptanceRunnerTests.\(UUID().uuidString)")),
            cleanupTimeoutSeconds: 0
        )

        await runner.run()
        let rows = try String(contentsOf: outputURL, encoding: .utf8)
            .split(separator: "\n")
            .map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
        await harness.waitUntilPreviewCancellationStarts()

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first?["cycle_number"] as? Int, 1)
        XCTAssertEqual(rows.first?["result_category"] as? String, "failure_cleanup_timeout")
        XCTAssertEqual(harness.startCount, 1)
        XCTAssertEqual(harness.state.snapshot.status, .failed)
        XCTAssertEqual(harness.state.snapshot.message, "Could not start recording.")
        XCTAssertTrue(try harness.store.list().isEmpty)
        XCTAssertEqual(harness.copyCount, 0)
        XCTAssertEqual(harness.organizationDispatchCount, 0)

        harness.completePreviewCancellation()
        await harness.drainCallbacks()
    }

    func testWriterCreatesOnlyNewFilesWithoutModifyingExistingOrSymlinkSentinels() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V02AcceptanceRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sentinel = Data("sentinel".utf8)

        let newURL = directory.appendingPathComponent("new.jsonl")
        let writer = try V02JSONLWriter(url: newURL)
        try writer.append(["row_type": "test"])
        XCTAssertFalse(try Data(contentsOf: newURL).isEmpty)

        let existingURL = directory.appendingPathComponent("existing.jsonl")
        try sentinel.write(to: existingURL)
        XCTAssertThrowsError(try V02JSONLWriter(url: existingURL))
        XCTAssertEqual(try Data(contentsOf: existingURL), sentinel)

        let targetURL = directory.appendingPathComponent("target.jsonl")
        let symlinkURL = directory.appendingPathComponent("link.jsonl")
        try sentinel.write(to: targetURL)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetURL)
        XCTAssertThrowsError(try V02JSONLWriter(url: symlinkURL))
        XCTAssertEqual(try Data(contentsOf: targetURL), sentinel)
    }

    func testP95UsesTheNinetyFifthSortedSample() {
        XCTAssertNil(V02AcceptanceMetrics.percentile95([]))
        XCTAssertEqual(V02AcceptanceMetrics.percentile95(Array(1...100).reversed()), 95)
        XCTAssertEqual(V02AcceptanceMetrics.percentile95(Array(1...20).reversed()), 19)
    }

    func testSummaryRequiresExactlyOneHundredPassingCyclesAtEveryBoundary() {
        let boundaryRows = (1...100).map {
            makeCycle(
                number: $0,
                firstPreviewMilliseconds: 800,
                stopToLocalFinalMilliseconds: 1_500,
                stopToCopyMilliseconds: $0 == 100 ? 3_000 : 2_000
            )
        }

        let boundary = V02AcceptanceMetrics.summarize(cycles: boundaryRows, requestedCycles: 100)
        XCTAssertEqual(boundary.firstPreviewP95Milliseconds, 800)
        XCTAssertEqual(boundary.stopToLocalFinalP95Milliseconds, 1_500)
        XCTAssertEqual(boundary.stopToCopyP95Milliseconds, 2_000)
        XCTAssertEqual(boundary.stopToCopyMaximumMilliseconds, 3_000)
        XCTAssertTrue(boundary.m10Eligible)
        XCTAssertTrue(boundary.m10Passed)
        XCTAssertEqual(boundary.resultCategory, "m10_passed")

        XCTAssertFalse(V02AcceptanceMetrics.summarize(
            cycles: boundaryRows.map { row in
                makeCycle(number: row.cycleNumber, firstPreviewMilliseconds: 801)
            },
            requestedCycles: 100
        ).m10Passed)
        XCTAssertFalse(V02AcceptanceMetrics.summarize(
            cycles: boundaryRows.map { row in
                makeCycle(number: row.cycleNumber, stopToLocalFinalMilliseconds: 1_501)
            },
            requestedCycles: 100
        ).m10Passed)
        XCTAssertFalse(V02AcceptanceMetrics.summarize(
            cycles: boundaryRows.map { row in
                makeCycle(number: row.cycleNumber, stopToCopyMilliseconds: 2_001)
            },
            requestedCycles: 100
        ).m10Passed)
        XCTAssertFalse(V02AcceptanceMetrics.summarize(
            cycles: boundaryRows.enumerated().map { index, row in
                makeCycle(number: row.cycleNumber, stopToCopyMilliseconds: index == 0 ? 3_001 : 2_000)
            },
            requestedCycles: 100
        ).m10Passed)

        let rehearsal = V02AcceptanceMetrics.summarize(cycles: Array(boundaryRows.prefix(3)), requestedCycles: 3)
        XCTAssertFalse(rehearsal.m10Eligible)
        XCTAssertFalse(rehearsal.m10Passed)
        XCTAssertEqual(rehearsal.resultCategory, "m10_ineligible")
    }

    func testSummaryRejectsEachRequiredFailureCondition() {
        let cases: [(name: String, makeRow: (Int) -> V02AcceptanceCycleEvidence)] = [
            ("lost record", { number in
                self.makeCycle(number: number, sessionID: self.sessionID(number), recordDelta: number == 1 ? 0 : 1)
            }),
            ("duplicate copy", { number in
                self.makeCycle(number: number, sessionID: self.sessionID(number), copyChangeCountDelta: number == 1 ? 2 : 1)
            }),
            ("organization recopy", { number in
                self.makeCycle(number: number, sessionID: self.sessionID(number), organizationDidNotRecopy: number != 1)
            }),
            ("duplicate session ID", { number in
                self.makeCycle(number: number, sessionID: self.sessionID(number == 2 ? 1 : number))
            }),
            ("failed cycle", { number in
                self.makeCycle(
                    number: number,
                    sessionID: self.sessionID(number),
                    resultCategory: number == 1 ? "local_delivery_failed" : "passed"
                )
            })
        ]

        for testCase in cases {
            let rows = (1...100).map(testCase.makeRow)
            XCTAssertFalse(
                V02AcceptanceMetrics.summarize(cycles: rows, requestedCycles: 100).m10Passed,
                testCase.name
            )
        }
    }

    func testMissingInvalidAndInconsistentDeliveryEvidenceCannotPassAcceptance() throws {
        let missingSource = makeCycle(number: 1, deliverySource: nil, polishState: .notRequested)
        XCTAssertFalse(missingSource.hasValidDeliveryEvidence)

        let missingState = makeCycle(number: 2, deliverySource: .local, polishState: nil)
        XCTAssertFalse(missingState.hasValidDeliveryEvidence)

        let invalid = makeCycle(number: 3, deliverySource: .polished, polishState: .timedOut)
        XCTAssertFalse(invalid.hasValidDeliveryEvidence)

        let valid = makeCycle(number: 4, deliverySource: .local, polishState: .notRequested)
        XCTAssertTrue(valid.hasValidDeliveryEvidence)

        let encodedMissingSource = try JSONSerialization.jsonObject(with: JSONEncoder().encode(missingSource)) as? [String: Any]
        XCTAssertTrue(encodedMissingSource?["delivery_source"] is NSNull)
        XCTAssertEqual(encodedMissingSource?["polish_state"] as? String, TranscriptPolishState.notRequested.rawValue)

        let encodedMissingState = try JSONSerialization.jsonObject(with: JSONEncoder().encode(missingState)) as? [String: Any]
        XCTAssertEqual(encodedMissingState?["delivery_source"] as? String, TranscriptDeliverySource.local.rawValue)
        XCTAssertTrue(encodedMissingState?["polish_state"] is NSNull)

        let encodedValid = try JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any]
        XCTAssertEqual(encodedValid?["delivery_source"] as? String, TranscriptDeliverySource.local.rawValue)
        XCTAssertEqual(encodedValid?["polish_state"] as? String, TranscriptPolishState.notRequested.rawValue)

        let rows = (1...100).map { number in
            makeCycle(number: number, deliverySource: number == 1 ? nil : .local, polishState: .notRequested)
        }
        XCTAssertFalse(V02AcceptanceMetrics.summarize(cycles: rows, requestedCycles: 100).m10Passed)
    }

    func testMissingNegativeAndInvertedReceiptTimingsCannotPassRowsOrSummary() {
        let cases: [(String, Int?, Int?)] = [
            ("missing local final", nil, 630),
            ("missing copy", 626, nil),
            ("negative local final", -1, 630),
            ("negative copy", 0, -1),
            ("copy before local final", 631, 630),
        ]

        for (name, localFinal, copy) in cases {
            let invalid = makeCycle(
                number: 1,
                stopToLocalFinalMilliseconds: localFinal,
                stopToCopyMilliseconds: copy
            )
            XCTAssertFalse(invalid.hasValidDeliveryEvidence, name)
            let rows = (1...100).map { number in
                number == 1 ? invalid : makeCycle(number: number, sessionID: sessionID(number))
            }
            XCTAssertFalse(
                V02AcceptanceMetrics.summarize(cycles: rows, requestedCycles: 100).m10Passed,
                name
            )
        }
    }

    func testEvidenceEncodingContainsOnlyTheExplicitMetadataAllowlist() throws {
        let encoder = JSONEncoder()
        let cycleKeys = try encodedKeys(encoder.encode(makeCycle(number: 1)))
        XCTAssertEqual(cycleKeys, [
            "copy_change_count_delta",
            "cycle_number",
            "delivery_source",
            "delivery_status",
            "first_preview_milliseconds",
            "immediate_equals_delivered",
            "organization_did_not_recopy",
            "organization_terminal_category",
            "polish_elapsed_ms",
            "polish_state",
            "post_organization_equals_delivered",
            "record_delta",
            "result_category",
            "row_type",
            "session_id",
            "stop_to_copy_ms",
            "stop_to_local_final_ms"
        ])

        let encoded = try String(decoding: encoder.encode(makeCycle(number: 1)), as: UTF8.self)
        for prohibited in ["submitted_text", "corrected_text", "local_cleaned_text", "polished_text"] {
            XCTAssertFalse(encoded.contains(prohibited), "JSONL must not emit \(prohibited)")
        }

        let summaryKeys = try encodedKeys(encoder.encode(V02AcceptanceMetrics.summarize(
            cycles: [makeCycle(number: 1)],
            requestedCycles: 1
        )))
        XCTAssertEqual(summaryKeys, [
            "completed_cycles",
            "duplicate_copy_count",
            "first_preview_maximum_milliseconds",
            "first_preview_p95_milliseconds",
            "lost_record_count",
            "m10_eligible",
            "m10_passed",
            "organization_recopy_count",
            "requested_cycles",
            "result_category",
            "row_type",
            "stop_to_copy_maximum_milliseconds",
            "stop_to_copy_p95_milliseconds",
            "stop_to_local_final_maximum_milliseconds",
            "stop_to_local_final_p95_milliseconds",
            "unique_session_id_count"
        ])
    }

    func testAppDelegateStartsAcceptanceHookOnlyAtLaunch() throws {
        let suiteName = "V02AcceptanceRunnerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let keychain = try TemporaryKeychain()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            keychain.delete()
        }
        var controllerStarts = 0
        var runnerStarts = 0
        let delegate = TSBAppDelegate(
            controller: AppController(),
            settingsModel: SettingsModel(store: OrganizationSettingsStore(
                defaults: defaults,
                secretStore: KeychainSecretStore(
                    service: "V02AcceptanceRunnerTests.\(UUID().uuidString)",
                    account: "api-key",
                    keychain: keychain.reference
                )
            )),
            startController: { controllerStarts += 1 },
            stopController: {},
            startAcceptanceRunner: { runnerStarts += 1 }
        )

        XCTAssertEqual(runnerStarts, 0)
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertEqual(controllerStarts, 1)
        XCTAssertEqual(runnerStarts, 1)
    }

    private func makeCycle(
        number: Int,
        sessionID: UUID = UUID(),
        firstPreviewMilliseconds: Int = 800,
        stopToLocalFinalMilliseconds: Int? = 1_500,
        stopToCopyMilliseconds: Int? = 2_000,
        deliverySource: TranscriptDeliverySource? = .local,
        polishState: TranscriptPolishState? = .notRequested,
        recordDelta: Int? = 1,
        copyChangeCountDelta: Int? = 1,
        organizationDidNotRecopy: Bool = true,
        resultCategory: String = "passed"
    ) -> V02AcceptanceCycleEvidence {
        V02AcceptanceCycleEvidence(
            cycleNumber: number,
            sessionID: sessionID,
            firstPreviewMilliseconds: firstPreviewMilliseconds,
            stopToLocalFinalMilliseconds: stopToLocalFinalMilliseconds,
            polishElapsedMilliseconds: 0,
            stopToCopyMilliseconds: stopToCopyMilliseconds,
            deliveryStatus: "copied",
            deliverySource: deliverySource,
            polishState: polishState,
            recordDelta: recordDelta,
            copyChangeCountDelta: copyChangeCountDelta,
            organizationTerminalCategory: "organized_local",
            immediateEqualsDelivered: true,
            postOrganizationEqualsDelivered: true,
            organizationDidNotRecopy: organizationDidNotRecopy,
            resultCategory: resultCategory
        )
    }

    private func sessionID(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }

    private func encodedKeys(_ data: Data) throws -> [String] {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return object.keys.sorted()
    }

    private func configuredRun(in directory: URL) throws -> ([String: String], URL) {
        let wavURL = directory.appendingPathComponent("input.wav")
        let outputURL = directory.appendingPathComponent("evidence.jsonl")
        let modelURL = directory.appendingPathComponent("paraformer", isDirectory: true)
        try Data().write(to: wavURL)
        try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: false)
        for file in ParaformerModelLocation.requiredFileNames {
            try Data(file.utf8).write(to: modelURL.appendingPathComponent(file))
        }
        let manifest = try ParaformerModelLocation.requiredFileNames.map { file in
            let data = try Data(contentsOf: modelURL.appendingPathComponent(file))
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return "\(digest)  \(file)"
        }.joined(separator: "\n") + "\n"
        try manifest.write(to: modelURL.appendingPathComponent("manifest.sha256"), atomically: true, encoding: .utf8)
        return ([
            "TSB_V02_ACCEPTANCE_RUN": "1",
            "TSB_V02_ACCEPTANCE_WAV": wavURL.path,
            "TSB_V02_ACCEPTANCE_OUTPUT": outputURL.path,
            "TSB_V02_ACCEPTANCE_CYCLES": "1",
            "TSB_PARAFORMER_MODEL_DIR": modelURL.path,
        ], outputURL)
    }

    private func assertSinglePermissionSetupFailure(at outputURL: URL) throws {
        let rows = try String(contentsOf: outputURL, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(rows.first).utf8)) as? [String: String])
        XCTAssertEqual(row, [
            "result_category": "microphone_permission_denied",
            "row_type": "setup",
        ])
    }

    private func assertNoAcceptanceRuntimeSideEffects(_ harness: RunnerFailureHarness) throws {
        XCTAssertEqual(harness.startCount, 0)
        XCTAssertEqual(harness.stopCount, 0)
        XCTAssertEqual(harness.copyCount, 0)
        XCTAssertEqual(harness.organizationDispatchCount, 0)
        XCTAssertTrue(try harness.store.list().isEmpty)
        XCTAssertEqual(harness.controller.state.snapshot.status, .idle)
        XCTAssertNil(harness.controller.state.snapshot.sessionID)
    }
}

@MainActor
private final class RunnerFailureHarness {
    let state = AppState()
    let store: TranscriptStore
    let pasteboard = NSPasteboard(name: .init("V02AcceptanceRunnerTests.\(UUID().uuidString)"))
    private var onFinished: ((RecordedAudio) -> Void)?
    private var onPreview: ((SessionID, String) -> Void)?
    private var recorderSessionID: SessionID?
    private let suspendsOrganization: Bool
    private let suspendsPreviewCancellation: Bool
    private let finishesOnStop: Bool
    private let throwsOnRecordingStart: Bool
    private let deliveryReceiptOverride: TranscriptDeliveryReceipt?
    private var organizationContinuation: UnsafeContinuation<OrganizationOutput, Never>?
    private var previewCancellationContinuation: UnsafeContinuation<Void, Never>?
    private(set) var stopCount = 0
    private(set) var startCount = 0
    private(set) var cancelCount = 0
    private(set) var previewCancellationCount = 0
    private(set) var copyCount = 0
    private(set) var organizationDispatchCount = 0

    private(set) lazy var coordinator = SessionCoordinator(
        dependencies: .init(
            startRecording: { [weak self] sessionID, onPreview, _, _, onFinished, _ in
                guard let self else { return }
                startCount += 1
                if throwsOnRecordingStart { throw RunnerFailureHarnessError.recordingStart }
                recorderSessionID = sessionID
                self.onPreview = onPreview
                self.onFinished = onFinished
            },
            stopRecording: { [weak self] in
                guard let self else { return }
                stopCount += 1
                if finishesOnStop {
                    recorderSessionID = nil
                    onFinished?(RecordedAudio(
                        url: FileManager.default.temporaryDirectory.appendingPathComponent("V02AcceptanceRunnerTests-late.wav"),
                        durationMilliseconds: 1
                    ))
                }
            },
            cancelRecording: { [weak self] sessionID in
                guard let self, recorderSessionID == sessionID else { return false }
                recorderSessionID = nil
                cancelCount += 1
                return true
            },
            finishPreview: { _ in "late local text" },
            cancelPreview: { [weak self] _ in
                guard let self else { return }
                previewCancellationCount += 1
                if suspendsPreviewCancellation {
                    await withUnsafeContinuation { previewCancellationContinuation = $0 }
                }
            },
            transcribe: { _ in
                TranscriptionResult(text: "late local text", detectedLanguage: "zh", eventTags: [], latencyMilliseconds: 1)
            },
            clean: { CleanResult(text: $0, edits: []) },
            save: { [weak self] record in try self?.store.save(record) },
            updateDeliveryStatus: { [weak self] sessionID, status in
                try self?.store.updateDeliveryStatus(id: sessionID, to: status)
            },
            updateDelivery: { [weak self] sessionID, status, receipt in
                guard let self else { return }
                try store.updateDelivery(
                    id: sessionID,
                    status: status,
                    receipt: deliveryReceiptOverride ?? receipt
                )
            },
            copy: { [weak self] text in
                guard let self else { return false }
                copyCount += 1
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                return true
            },
            loadPersistedRecords: { [] },
            updateOrganization: { [weak self] sessionID, organization in
                try self?.store.updateOrganization(id: sessionID, to: organization)
            },
            currentOrganizationSettings: {
                OrganizationSettings(endpoint: try! OrganizationEndpointSettings(
                    baseURL: URL(string: "http://127.0.0.1:1/v1/chat/completions")!,
                    model: "test-local"
                ))
            },
            historySuggestions: { _ in
                HistorySuggestions(suggestedSummaries: [], localRecordByCandidateID: [:])
            },
            organize: { [weak self] _, segments, _, _, _, willDispatch in
                try willDispatch(try OrganizationEndpointSettings(
                    baseURL: URL(string: "http://127.0.0.1:1/v1/chat/completions")!,
                    model: "test-local"
                ))
                self?.organizationDispatchCount += 1
                let output = OrganizationOutput(
                    noResultReason: nil,
                    numberedPoints: segments.enumerated().map {
                        NumberedPoint(number: $0.offset + 1, text: $0.element.text, sourceSegmentIDs: [$0.element.id])
                    },
                    knownRecordLinks: [],
                    speculativeConnections: []
                )
                guard self?.suspendsOrganization == true else { return output }
                return await withUnsafeContinuation { self?.organizationContinuation = $0 }
            },
            scheduleSecondaryRemoval: { _, _ in }
        ),
        onSnapshot: { [weak state] snapshot in state?.snapshot = snapshot }
    )

    private(set) lazy var controller = AppController(state: state, coordinator: coordinator)

    init(
        recordsDirectory: URL,
        suspendsOrganization: Bool = false,
        suspendsPreviewCancellation: Bool = false,
        finishesOnStop: Bool = false,
        throwsOnRecordingStart: Bool = false,
        deliveryReceiptOverride: TranscriptDeliveryReceipt? = nil
    ) {
        store = TranscriptStore(directory: recordsDirectory)
        self.suspendsOrganization = suspendsOrganization
        self.suspendsPreviewCancellation = suspendsPreviewCancellation
        self.finishesOnStop = finishesOnStop
        self.throwsOnRecordingStart = throwsOnRecordingStart
        self.deliveryReceiptOverride = deliveryReceiptOverride
    }

    func deliverLateFinishedAudio() async {
        recorderSessionID = nil
        onFinished?(RecordedAudio(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("V02AcceptanceRunnerTests-late.wav"),
            durationMilliseconds: 1
        ))
        await drainCallbacks()
    }

    func deliverOneSession() async {
        controller.toggleForDevelopment()
        await wait { self.state.snapshot.status == .recording }
        controller.toggleForDevelopment()
        await wait { self.stopCount == 1 }
        await deliverLateFinishedAudio()
        await wait { self.organizationDispatchCount == 1 }
    }

    func completeOrganization() {
        let segments = [try! TextSegment(id: "c1", text: "late local text")]
        organizationContinuation?.resume(returning: OrganizationOutput(
            noResultReason: nil,
            numberedPoints: [NumberedPoint(number: 1, text: "late local text", sourceSegmentIDs: [segments[0].id])],
            knownRecordLinks: [],
            speculativeConnections: []
        ))
        organizationContinuation = nil
    }

    func publishPreview(_ text: String) {
        guard let sessionID = state.snapshot.sessionID else { return }
        onPreview?(sessionID, text)
    }

    func drainCallbacks() async {
        for _ in 0..<100 { await Task.yield() }
    }

    func waitUntilRecordingStarts() async {
        await wait { self.startCount == 1 }
    }

    func waitUntilOrganizationCancelled() async {
        await wait {
            if case .failed = self.state.snapshot.organizationPhase { return true }
            return false
        }
    }

    func waitUntilPreviewCancellationStarts() async {
        await wait { self.previewCancellationCount == 1 }
    }

    func completePreviewCancellation() {
        previewCancellationContinuation?.resume()
        previewCancellationContinuation = nil
    }

    private func wait(until condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for runner harness state")
    }
}

private enum RunnerFailureHarnessError: Error {
    case recordingStart
}

@MainActor
private final class RunnerBarrier {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
