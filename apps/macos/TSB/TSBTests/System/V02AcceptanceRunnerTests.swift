import AppKit
import Foundation
import XCTest
@testable import TSB

@MainActor
final class V02AcceptanceRunnerTests: XCTestCase {
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

    func testRunnerRequiresExistingMicrophoneAuthorizationBeforeAnySideEffect() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V02AcceptanceRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let wavURL = directory.appendingPathComponent("input.wav")
        let outputURL = directory.appendingPathComponent("evidence.jsonl")
        try Data().write(to: wavURL)
        let controller = AppController()

        V02AcceptanceRunner.startIfConfigured(
            controller: controller,
            environment: [
                "TSB_V02_ACCEPTANCE_RUN": "1",
                "TSB_V02_ACCEPTANCE_WAV": wavURL.path,
                "TSB_V02_ACCEPTANCE_OUTPUT": outputURL.path,
                "TSB_V02_ACCEPTANCE_CYCLES": "1"
            ],
            microphonePermissionGranted: { false }
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(controller.state.snapshot.status, .idle)
        XCTAssertNil(controller.state.snapshot.sessionID)
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

    func testEvidenceEncodingContainsOnlyTheExplicitMetadataAllowlist() throws {
        let encoder = JSONEncoder()
        let cycleKeys = try encodedKeys(encoder.encode(makeCycle(number: 1)))
        XCTAssertEqual(cycleKeys, [
            "copy_change_count_delta",
            "cycle_number",
            "delivery_status",
            "first_preview_milliseconds",
            "immediate_equals_local",
            "organization_did_not_recopy",
            "organization_terminal_category",
            "post_organization_equals_local",
            "record_delta",
            "result_category",
            "row_type",
            "session_id",
            "stop_to_copy_milliseconds",
            "stop_to_local_final_milliseconds"
        ])

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
        stopToLocalFinalMilliseconds: Int = 1_500,
        stopToCopyMilliseconds: Int = 2_000,
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
            stopToCopyMilliseconds: stopToCopyMilliseconds,
            deliveryStatus: "copied",
            recordDelta: recordDelta,
            copyChangeCountDelta: copyChangeCountDelta,
            organizationTerminalCategory: "organized_local",
            immediateEqualsLocal: true,
            postOrganizationEqualsLocal: true,
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
}
