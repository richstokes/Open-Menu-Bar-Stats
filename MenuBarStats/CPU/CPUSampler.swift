import Foundation

actor CPUSampler {
    private let tickSource: MachCPUTickSource
    private var previousTicks: [CPUTicks]?

    init(tickSource: MachCPUTickSource = MachCPUTickSource()) {
        self.tickSource = tickSource
    }

    func sample(at timestamp: Date = Date()) throws -> CPUSnapshot? {
        let currentTicks = try tickSource.read()
        defer {
            previousTicks = currentTicks
        }

        guard let previousTicks else {
            return nil
        }

        return CPUUsageCalculator.makeSnapshot(
            previous: previousTicks,
            current: currentTicks,
            timestamp: timestamp
        )
    }

    func reset() {
        previousTicks = nil
    }
}
