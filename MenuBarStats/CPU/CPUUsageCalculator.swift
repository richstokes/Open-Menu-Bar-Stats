import Foundation

enum CPUUsageCalculator {
    static func makeSnapshot(
        previous: [CPUTicks],
        current: [CPUTicks],
        timestamp: Date = Date()
    ) -> CPUSnapshot? {
        guard !current.isEmpty, previous.count == current.count else {
            return nil
        }

        var totalBusy: UInt64 = 0
        var totalTicks: UInt64 = 0
        var coreReadings: [CPUCoreReading] = []
        coreReadings.reserveCapacity(current.count)

        for (index, pair) in zip(previous, current).enumerated() {
            let user = UInt64(pair.1.user &- pair.0.user)
            let system = UInt64(pair.1.system &- pair.0.system)
            let nice = UInt64(pair.1.nice &- pair.0.nice)
            let idle = UInt64(pair.1.idle &- pair.0.idle)
            let busy = user + system + nice
            let ticks = busy + idle
            let usage = ticks == 0 ? 0 : Double(busy) / Double(ticks)

            totalBusy += busy
            totalTicks += ticks
            coreReadings.append(CPUCoreReading(id: index, usage: usage))
        }

        guard totalTicks > 0 else {
            return nil
        }

        return CPUSnapshot(
            cores: coreReadings,
            overallUsage: Double(totalBusy) / Double(totalTicks),
            timestamp: timestamp
        )
    }
}
