import XCTest
@testable import SenseVoiceProbe

final class ProbeMetricsTests: XCTestCase {
    func testActivePeakDeltaSubtractsBaselineAndNeverUnderflows() {
        XCTAssertEqual(activePeakDelta(baselineRSSBytes: 400, peakRSSBytes: 900), 500)
        XCTAssertEqual(activePeakDelta(baselineRSSBytes: 900, peakRSSBytes: 400), 0)
    }
}
