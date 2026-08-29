import Foundation
import Observation

@MainActor
@Observable
final class CPUMonitor {
    private(set) var snapshot: CPUSnapshot?
    private(set) var errorMessage: String?
    private(set) var memorySnapshot: MemorySnapshot?
    private(set) var memoryErrorMessage: String?
    private(set) var isRunning = false

    @ObservationIgnored
    private let sampler: CPUSampler

    @ObservationIgnored
    private let memorySource: any MemoryReading

    init(
        snapshot: CPUSnapshot? = nil,
        memorySnapshot: MemorySnapshot? = nil,
        sampler: CPUSampler = CPUSampler(),
        memorySource: any MemoryReading = MachMemorySource()
    ) {
        self.snapshot = snapshot
        self.memorySnapshot = memorySnapshot
        self.sampler = sampler
        self.memorySource = memorySource
    }

    func run() async {
        // A MenuBarExtra label can be replaced before SwiftUI finishes cancelling
        // its previous task. Wait for that task to hand off instead of letting the
        // replacement return and accidentally leave the app without a sampler.
        while isRunning {
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
        }
        guard !Task.isCancelled else { return }

        isRunning = true
        defer { isRunning = false }

        while !Task.isCancelled {
            let timestamp = Date()
            updateMemory(at: timestamp)

            do {
                if let nextSnapshot = try await sampler.sample(at: timestamp) {
                    snapshot = nextSnapshot
                    errorMessage = nil
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                break
            }
        }
    }

    private func updateMemory(at timestamp: Date) {
        do {
            memorySnapshot = try memorySource.read(at: timestamp)
            memoryErrorMessage = nil
        } catch {
            memoryErrorMessage = error.localizedDescription
        }
    }
}
