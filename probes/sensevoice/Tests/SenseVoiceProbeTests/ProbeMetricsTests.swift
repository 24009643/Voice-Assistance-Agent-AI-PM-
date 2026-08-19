import XCTest
@testable import SenseVoiceProbe

final class ProbeMetricsTests: XCTestCase {
    func testActivePeakDeltaSubtractsBaselineAndNeverUnderflows() {
        XCTAssertEqual(activePeakDelta(baselineRSSBytes: 400, peakRSSBytes: 900), 500)
        XCTAssertEqual(activePeakDelta(baselineRSSBytes: 900, peakRSSBytes: 400), 0)
    }

    func testChunkedSamplesPreserveEveryFrameInOrder() {
        let chunks = chunkedSamples([0, 1, 2, 3, 4, 5, 6], maximumFrameCount: 3)
        XCTAssertEqual(chunks, [[0, 1, 2], [3, 4, 5], [6]])
        XCTAssertEqual(chunks.flatMap { $0 }, [0, 1, 2, 3, 4, 5, 6])
    }
}
