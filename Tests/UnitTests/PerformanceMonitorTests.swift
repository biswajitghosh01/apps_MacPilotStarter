import XCTest
@testable import MacPilot

final class PerformanceMonitorTests: XCTestCase {
    func testNormalizedLoadIsRelativeToLogicalProcessors() {
        let reading = PerformanceReading(
            sampledAt: Date(),
            oneMinuteLoadAverage: 4,
            fiveMinuteLoadAverage: 3,
            fifteenMinuteLoadAverage: 2,
            memoryUsedBytes: 1,
            memoryAvailableBytes: 1,
            logicalProcessorCount: 8,
            physicalMemoryBytes: 16
        )
        XCTAssertEqual(reading.normalizedOneMinuteLoad ?? -1, 0.5, accuracy: 0.0001)
    }

    func testNormalizedLoadIsUnavailableWithoutProcessorCount() {
        let reading = PerformanceReading(
            sampledAt: Date(),
            oneMinuteLoadAverage: 1,
            fiveMinuteLoadAverage: 1,
            fifteenMinuteLoadAverage: 1,
            memoryUsedBytes: nil,
            memoryAvailableBytes: nil,
            logicalProcessorCount: 0,
            physicalMemoryBytes: 0
        )
        XCTAssertNil(reading.normalizedOneMinuteLoad)
    }

    func testPercentClampsAndRejectsNonFiniteValues() {
        XCTAssertEqual(PerformanceReading.percent(0.5) ?? -1, 50, accuracy: 0.0001)
        XCTAssertEqual(PerformanceReading.percent(2) ?? -1, 100, accuracy: 0.0001)
        XCTAssertEqual(PerformanceReading.percent(-1) ?? -1, 0, accuracy: 0.0001)
        XCTAssertNil(PerformanceReading.percent(.nan))
        XCTAssertNil(PerformanceReading.percent(nil))
    }
}
