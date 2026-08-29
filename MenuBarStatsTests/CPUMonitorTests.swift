import AppKit
import Foundation
import XCTest
@testable import MenuBarStats

final class CPUMonitorTests: XCTestCase {
    func testPublicThermalStatesHaveAccurateLabels() {
        XCTAssertEqual(SystemThermalState(.nominal).title, "OK")
        XCTAssertEqual(SystemThermalState(.fair).title, "Fair")
        XCTAssertEqual(SystemThermalState(.serious).title, "Serious")
        XCTAssertEqual(SystemThermalState(.critical).title, "Critical")
    }

    func testOnlyExceptionalThermalStatesAddMenuBarText() {
        XCTAssertNil(SystemThermalState.nominal.menuBarTitle)
        XCTAssertEqual(SystemThermalState.fair.menuBarTitle, "Fair")
        XCTAssertEqual(SystemThermalState.serious.menuBarTitle, "Serious")
        XCTAssertEqual(SystemThermalState.critical.menuBarTitle, "Critical")
    }

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
    func testDisabledMemoryDoesNotReadMemoryCounters() async throws {
        let memorySource = CountingMemorySource()
        let monitor = CPUMonitor(memorySource: memorySource)
        let task = Task { await monitor.run(samplesMemory: false) }

        try await waitUntil { monitor.isRunning }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(memorySource.readCount, 0)

        task.cancel()
        try await waitUntil { !monitor.isRunning }
    }

    @MainActor
    func testEnabledMemoryReadsImmediately() async throws {
        let memorySource = CountingMemorySource()
        let monitor = CPUMonitor(memorySource: memorySource)
        let task = Task { await monitor.run(samplesMemory: true) }

        try await waitUntil { monitor.memorySnapshot != nil }
        XCTAssertEqual(memorySource.readCount, 1)

        task.cancel()
        try await waitUntil { !monitor.isRunning }
    }

    @MainActor
    func testNewRunSupersedesExistingRunWithoutHandoffPolling() async throws {
        let memorySource = CountingMemorySource()
        let monitor = CPUMonitor(memorySource: memorySource)
        let firstTask = Task { await monitor.run(samplesMemory: true) }
        try await waitUntil { memorySource.readCount == 1 }

        let replacementTask = Task { await monitor.run(samplesMemory: true) }
        try await waitUntil { memorySource.readCount == 2 }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(memorySource.readCount, 2)

        firstTask.cancel()
        replacementTask.cancel()
        try await waitUntil { !monitor.isRunning }
    }

    @MainActor
    func testCancellationDoesNotPublishAnInFlightMemoryFailure() async throws {
        let memorySource = DelayedFailingMemorySource()
        let monitor = CPUMonitor(memorySource: memorySource)
        let task = Task { await monitor.run(samplesMemory: true) }

        try await waitUntil { memorySource.readCount == 1 }
        task.cancel()
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertNil(monitor.memoryErrorMessage)
        try await waitUntil { !monitor.isRunning }
    }

    @MainActor
    func testScreenActivityMessagesUpdateSamplingState() async throws {
        let monitor = CPUMonitor()
        let workspace = NSWorkspace.shared
        let notificationCenter = workspace.notificationCenter

        notificationCenter.post(NSWorkspace.ScreensDidSleepMessage(), subject: workspace)
        try await waitUntil { !monitor.isScreenAwake }

        notificationCenter.post(NSWorkspace.ScreensDidWakeMessage(), subject: workspace)
        try await waitUntil { monitor.isScreenAwake }
    }

    @MainActor
    func testLoginSessionMessagesUpdateSamplingState() async throws {
        let monitor = CPUMonitor()
        let workspace = NSWorkspace.shared
        let notificationCenter = workspace.notificationCenter

        notificationCenter.post(NSWorkspace.SessionDidResignActiveMessage(), subject: workspace)
        XCTAssertFalse(monitor.isSessionActive)

        notificationCenter.post(NSWorkspace.SessionDidBecomeActiveMessage(), subject: workspace)
        XCTAssertTrue(monitor.isSessionActive)
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

private final class CountingMemorySource: MemoryReading, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var readCount: Int {
        lock.withLock { count }
    }

    func read(at timestamp: Date) throws -> MemorySnapshot {
        lock.withLock {
            count += 1
        }

        return MemorySnapshot(
            usedBytes: 4_096,
            totalBytes: 8_192,
            timestamp: timestamp
        )
    }
}

private final class DelayedFailingMemorySource: MemoryReading, @unchecked Sendable {
    private enum ExpectedFailure: LocalizedError {
        case unavailable

        var errorDescription: String? { "Expected memory read failure" }
    }

    private let lock = NSLock()
    private var count = 0

    var readCount: Int {
        lock.withLock { count }
    }

    func read(at timestamp: Date) throws -> MemorySnapshot {
        lock.withLock {
            count += 1
        }
        Thread.sleep(forTimeInterval: 0.1)
        throw ExpectedFailure.unavailable
    }
}
