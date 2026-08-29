import Foundation
import Observation

@MainActor
@Observable
final class CPUMonitor {
    private(set) var snapshot: CPUSnapshot?
    private(set) var errorMessage: String?
    private(set) var isRunning = false

    @ObservationIgnored
    private let sampler: CPUSampler

    init(snapshot: CPUSnapshot? = nil, sampler: CPUSampler = CPUSampler()) {
        self.snapshot = snapshot
        self.sampler = sampler
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
            do {
                if let nextSnapshot = try await sampler.sample() {
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
}
