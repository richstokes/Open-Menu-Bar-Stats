import XCTest
@testable import MenuBarStats

final class CPUUsageCalculatorTests: XCTestCase {
    func testKnownDeltasProduceExpectedUsage() throws {
        let previous = [ticks(user: 100, system: 50, idle: 200, nice: 0)]
        let current = [ticks(user: 110, system: 60, idle: 220, nice: 0)]

        let snapshot = try XCTUnwrap(
            CPUUsageCalculator.makeSnapshot(previous: previous, current: current)
        )

        XCTAssertEqual(snapshot.cores[0].usage, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.overallUsage, 0.5, accuracy: 0.000_001)
    }

    func testNiceTicksCountAsBusy() throws {
        let previous = [ticks(user: 0, system: 0, idle: 0, nice: 10)]
        let current = [ticks(user: 0, system: 0, idle: 30, nice: 20)]

        let snapshot = try XCTUnwrap(
            CPUUsageCalculator.makeSnapshot(previous: previous, current: current)
        )

        XCTAssertEqual(snapshot.cores[0].usage, 0.25, accuracy: 0.000_001)
    }

    func testOverallUsageUsesAggregatedTicks() throws {
        let previous = [
            ticks(user: 0, system: 0, idle: 0, nice: 0),
            ticks(user: 0, system: 0, idle: 0, nice: 0)
        ]
        let current = [
            ticks(user: 10, system: 0, idle: 0, nice: 0),
            ticks(user: 0, system: 0, idle: 90, nice: 0)
        ]

        let snapshot = try XCTUnwrap(
            CPUUsageCalculator.makeSnapshot(previous: previous, current: current)
        )

        XCTAssertEqual(snapshot.cores[0].usage, 1, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.cores[1].usage, 0, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.overallUsage, 0.1, accuracy: 0.000_001)
    }

    func testUInt32CountersCanWrap() throws {
        let previous = [ticks(user: UInt32.max - 4, system: 0, idle: 100, nice: 0)]
        let current = [ticks(user: 5, system: 0, idle: 110, nice: 0)]

        let snapshot = try XCTUnwrap(
            CPUUsageCalculator.makeSnapshot(previous: previous, current: current)
        )

        XCTAssertEqual(snapshot.cores[0].usage, 0.5, accuracy: 0.000_001)
    }

    func testZeroTotalDeltaIsUnavailable() {
        let values = [ticks(user: 1, system: 2, idle: 3, nice: 4)]

        XCTAssertNil(CPUUsageCalculator.makeSnapshot(previous: values, current: values))
    }

    func testChangedCoreCountIsUnavailable() {
        let previous = [ticks(user: 0, system: 0, idle: 0, nice: 0)]
        let current = [
            ticks(user: 1, system: 0, idle: 1, nice: 0),
            ticks(user: 1, system: 0, idle: 1, nice: 0)
        ]

        XCTAssertNil(CPUUsageCalculator.makeSnapshot(previous: previous, current: current))
    }

    func testBusiestCoreTieUsesLowestIndex() throws {
        let previous = [
            ticks(user: 0, system: 0, idle: 0, nice: 0),
            ticks(user: 0, system: 0, idle: 0, nice: 0)
        ]
        let current = [
            ticks(user: 5, system: 0, idle: 5, nice: 0),
            ticks(user: 10, system: 0, idle: 10, nice: 0)
        ]

        let snapshot = try XCTUnwrap(
            CPUUsageCalculator.makeSnapshot(previous: previous, current: current)
        )

        XCTAssertEqual(snapshot.busiestCore?.id, 0)
    }

    func testLiveMachReaderReturnsLogicalProcessors() throws {
        let values = try MachCPUTickSource().read()

        XCTAssertFalse(values.isEmpty)
    }

    private func ticks(
        user: UInt32,
        system: UInt32,
        idle: UInt32,
        nice: UInt32
    ) -> CPUTicks {
        CPUTicks(user: user, system: system, idle: idle, nice: nice)
    }
}
