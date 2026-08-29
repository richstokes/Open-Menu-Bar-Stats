import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class CPUMonitor {
    static let samplingInterval: Duration = .seconds(1)
    static let samplingTolerance: Duration = .milliseconds(100)

    private(set) var snapshot: CPUSnapshot?
    private(set) var errorMessage: String?
    private(set) var memorySnapshot: MemorySnapshot?
    private(set) var memoryErrorMessage: String?
    private(set) var thermalState: SystemThermalState
    private(set) var isScreenAwake = true
    private(set) var isSessionActive = true
    private(set) var isRunning = false

    @ObservationIgnored
    private let sampler: CPUSampler

    @ObservationIgnored
    private let memorySampler: MemorySampler

    @ObservationIgnored
    private var runGeneration: UInt64 = 0

    @ObservationIgnored
    private var screenSleepObserver: NotificationCenter.ObservationToken?

    @ObservationIgnored
    private var screenWakeObserver: NotificationCenter.ObservationToken?

    @ObservationIgnored
    private var sessionResignObserver: NotificationCenter.ObservationToken?

    @ObservationIgnored
    private var sessionBecomeActiveObserver: NotificationCenter.ObservationToken?

    @ObservationIgnored
    private var thermalStateObserver: NotificationCenter.ObservationToken?

    init(
        snapshot: CPUSnapshot? = nil,
        memorySnapshot: MemorySnapshot? = nil,
        thermalState: SystemThermalState = .current,
        sampler: CPUSampler = CPUSampler(),
        memorySource: any MemoryReading = MachMemorySource()
    ) {
        self.snapshot = snapshot
        self.memorySnapshot = memorySnapshot
        self.thermalState = thermalState
        self.sampler = sampler
        memorySampler = MemorySampler(source: memorySource)

        let workspace = NSWorkspace.shared
        screenSleepObserver = workspace.notificationCenter.addObserver(
            of: workspace,
            for: .screensDidSleep
        ) { [weak self] _ in
            await self?.setScreenAwake(false)
        }
        screenWakeObserver = workspace.notificationCenter.addObserver(
            of: workspace,
            for: .screensDidWake
        ) { [weak self] _ in
            await self?.setScreenAwake(true)
        }
        sessionResignObserver = workspace.notificationCenter.addObserver(
            of: workspace,
            for: .sessionDidResignActive
        ) { [weak self] _ in
            self?.setSessionActive(false)
        }
        sessionBecomeActiveObserver = workspace.notificationCenter.addObserver(
            of: workspace,
            for: .sessionDidBecomeActive
        ) { [weak self] _ in
            self?.setSessionActive(true)
        }

        let processInfo = ProcessInfo.processInfo
        thermalStateObserver = NotificationCenter.default.addObserver(
            of: processInfo,
            for: .thermalStateDidChange
        ) { [weak self] _ in
            await self?.refreshThermalState()
        }
    }

    func run(samplesMemory: Bool = false) async {
        guard !Task.isCancelled else { return }

        // SwiftUI can replace the MenuBarExtra label before its previous task has
        // finished cancelling. A generation handoff makes the newest task the sole
        // publisher without introducing a short-interval polling loop.
        runGeneration &+= 1
        let generation = runGeneration
        isRunning = true
        defer {
            if generation == runGeneration {
                isRunning = false
            }
        }

        let clock = ContinuousClock()
        var nextDeadline = clock.now

        while !Task.isCancelled, generation == runGeneration {
            let timestamp = Date()

            do {
                let nextSnapshot = try await sampler.sample(at: timestamp)
                guard !Task.isCancelled, generation == runGeneration else { break }

                if let nextSnapshot {
                    snapshot = nextSnapshot
                    errorMessage = nil
                }
            } catch {
                guard generation == runGeneration else { break }
                errorMessage = error.localizedDescription
            }

            if samplesMemory {
                await updateMemory(at: timestamp, generation: generation)
            }

            guard !Task.isCancelled, generation == runGeneration else { break }

            nextDeadline = nextDeadline.advanced(by: Self.samplingInterval)
            let now = clock.now
            if nextDeadline < now {
                nextDeadline = now.advanced(by: Self.samplingInterval)
            }

            do {
                try await Task.sleep(
                    until: nextDeadline,
                    tolerance: Self.samplingTolerance,
                    clock: clock
                )
            } catch {
                break
            }
        }
    }

    private func updateMemory(at timestamp: Date, generation: UInt64) async {
        do {
            let nextSnapshot = try await memorySampler.sample(at: timestamp)
            guard !Task.isCancelled, generation == runGeneration else { return }

            memorySnapshot = nextSnapshot
            memoryErrorMessage = nil
        } catch {
            guard generation == runGeneration else { return }
            memoryErrorMessage = error.localizedDescription
        }
    }

    private func setScreenAwake(_ isAwake: Bool) {
        guard isScreenAwake != isAwake else { return }
        isScreenAwake = isAwake
    }

    private func setSessionActive(_ isActive: Bool) {
        guard isSessionActive != isActive else { return }
        isSessionActive = isActive
    }

    private func refreshThermalState() {
        let currentThermalState = SystemThermalState.current
        guard thermalState != currentThermalState else { return }
        thermalState = currentThermalState
    }
}
