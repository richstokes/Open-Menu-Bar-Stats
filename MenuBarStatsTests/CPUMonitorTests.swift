import XCTest
@testable import MenuBarStats

final class CPUMonitorTests: XCTestCase {
    @MainActor
    func testReplacementTaskTakesOverAfterCancellation() async throws {
        let monitor = CPUMonitor()
        let firstTask = Task { await monitor.run() }
        try await waitUntil { monitor.isRunning }

        let replacementTask = Task { await monitor.run() }
        firstTask.cancel()

        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(monitor.isRunning)

        replacementTask.cancel()
        try await waitUntil { !monitor.isRunning }
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(condition())
    }
}
