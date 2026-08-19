import Foundation

struct SampleResult: Encodable {
    let kind = "sample"
    let id: String
    let expectedLanguage: String
    let detectedLanguage: String?
    let transcript: String
    let events: [String]
    let emotion: String?
    let latencyMilliseconds: Int
    let audioDurationSeconds: Double?
}

struct ProcessMetrics: Encodable {
    let kind = "process"
    let sampleCount: Int
    let coldLoadMilliseconds: Int
    let totalElapsedMilliseconds: Int
    let baselineRSSBytes: UInt64
    let peakRSSBytes: UInt64
    let activePeakRSSDeltaBytes: UInt64
}
