import Foundation

struct MemorySnapshot: Equatable, Sendable {
    let usedBytes: UInt64
    let totalBytes: UInt64
    let timestamp: Date

    var usage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    var clampedUsage: Double {
        min(max(usage, 0), 1)
    }

    var percentage: Int {
        Int((clampedUsage * 100).rounded())
    }
}

enum MemoryUsageCalculator {
    static func makeSnapshot(
        internalPages: UInt64,
        purgeablePages: UInt64,
        wiredPages: UInt64,
        compressedPages: UInt64,
        pageSize: UInt64,
        totalBytes: UInt64,
        timestamp: Date = Date()
    ) -> MemorySnapshot? {
        guard pageSize > 0, totalBytes > 0 else { return nil }

        // Approximate Activity Monitor's App Memory + Wired + Compressed breakdown.
        // Treat purgeable pages as reclaimable when approximating App Memory.
        let appPages = internalPages >= purgeablePages
            ? internalPages - purgeablePages
            : 0
        let usedPages = saturatingSum(appPages, wiredPages, compressedPages)
        let (calculatedBytes, overflowed) = usedPages.multipliedReportingOverflow(by: pageSize)
        let usedBytes = overflowed ? totalBytes : min(calculatedBytes, totalBytes)

        return MemorySnapshot(
            usedBytes: usedBytes,
            totalBytes: totalBytes,
            timestamp: timestamp
        )
    }

    private static func saturatingSum(_ values: UInt64...) -> UInt64 {
        values.reduce(0) { partialResult, value in
            let (sum, overflowed) = partialResult.addingReportingOverflow(value)
            return overflowed ? .max : sum
        }
    }
}
