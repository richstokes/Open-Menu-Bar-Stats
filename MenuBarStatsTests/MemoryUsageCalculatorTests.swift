import Foundation
import XCTest
@testable import MenuBarStats

final class MemoryUsageCalculatorTests: XCTestCase {
    func testKnownPageCountsProduceExpectedUsage() throws {
        let timestamp = Date(timeIntervalSince1970: 123)
        let snapshot = try XCTUnwrap(
            MemoryUsageCalculator.makeSnapshot(
                internalPages: 5,
                purgeablePages: 1,
                wiredPages: 2,
                compressedPages: 1,
                pageSize: 4_096,
                totalBytes: 10 * 4_096,
                timestamp: timestamp
            )
        )

        XCTAssertEqual(snapshot.usedBytes, 7 * 4_096)
        XCTAssertEqual(snapshot.totalBytes, 10 * 4_096)
        XCTAssertEqual(snapshot.usage, 0.7, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.percentage, 70)
        XCTAssertEqual(snapshot.timestamp, timestamp)
    }

    func testUsedMemoryIsClampedToPhysicalMemory() throws {
        let snapshot = try XCTUnwrap(
            MemoryUsageCalculator.makeSnapshot(
                internalPages: 100,
                purgeablePages: 0,
                wiredPages: 100,
                compressedPages: 100,
                pageSize: 4_096,
                totalBytes: 4_096
            )
        )

        XCTAssertEqual(snapshot.usedBytes, snapshot.totalBytes)
        XCTAssertEqual(snapshot.percentage, 100)
    }

    func testPurgeablePagesCannotUnderflowAppMemory() throws {
        let snapshot = try XCTUnwrap(
            MemoryUsageCalculator.makeSnapshot(
                internalPages: 1,
                purgeablePages: 2,
                wiredPages: 2,
                compressedPages: 1,
                pageSize: 4_096,
                totalBytes: 10 * 4_096
            )
        )

        XCTAssertEqual(snapshot.usedBytes, 3 * 4_096)
        XCTAssertEqual(snapshot.percentage, 30)
    }

    func testPageCountAdditionOverflowClampsToPhysicalMemory() throws {
        let snapshot = try XCTUnwrap(
            MemoryUsageCalculator.makeSnapshot(
                internalPages: .max,
                purgeablePages: 0,
                wiredPages: 1,
                compressedPages: 0,
                pageSize: 1,
                totalBytes: 4_096
            )
        )

        XCTAssertEqual(snapshot.usedBytes, snapshot.totalBytes)
        XCTAssertEqual(snapshot.percentage, 100)
    }

    func testByteCountOverflowClampsToPhysicalMemory() throws {
        let snapshot = try XCTUnwrap(
            MemoryUsageCalculator.makeSnapshot(
                internalPages: .max,
                purgeablePages: 0,
                wiredPages: 0,
                compressedPages: 0,
                pageSize: 2,
                totalBytes: 4_096
            )
        )

        XCTAssertEqual(snapshot.usedBytes, snapshot.totalBytes)
        XCTAssertEqual(snapshot.percentage, 100)
    }

    func testInvalidTotalsAreUnavailable() {
        XCTAssertNil(
            MemoryUsageCalculator.makeSnapshot(
                internalPages: 1,
                purgeablePages: 0,
                wiredPages: 1,
                compressedPages: 1,
                pageSize: 0,
                totalBytes: 4_096
            )
        )
        XCTAssertNil(
            MemoryUsageCalculator.makeSnapshot(
                internalPages: 1,
                purgeablePages: 0,
                wiredPages: 1,
                compressedPages: 1,
                pageSize: 4_096,
                totalBytes: 0
            )
        )
    }

    func testLiveMachReaderReturnsPlausibleMemory() throws {
        let snapshot = try MachMemorySource().read()

        XCTAssertGreaterThan(snapshot.totalBytes, 0)
        XCTAssertLessThanOrEqual(snapshot.usedBytes, snapshot.totalBytes)
        XCTAssertGreaterThanOrEqual(snapshot.clampedUsage, 0)
        XCTAssertLessThanOrEqual(snapshot.clampedUsage, 1)
    }
}
