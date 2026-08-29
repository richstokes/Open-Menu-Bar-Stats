import AppKit
import SwiftUI

struct CPUMenuView: View {
    let monitor: CPUMonitor
    @Bindable var preferences: AppPreferences

    private var displayedCores: [CPUCoreReading] {
        guard let snapshot = monitor.snapshot else { return [] }
        switch preferences.coreScope {
        case .all:
            return snapshot.cores
        case .busiest:
            return snapshot.busiestCore.map { [$0] } ?? []
        }
    }

    private var summary: String {
        guard let snapshot = monitor.snapshot else { return "Measuring CPU usage…" }
        switch preferences.coreScope {
        case .all:
            return "Overall \(snapshot.overallPercentage)% · \(snapshot.cores.count) cores"
        case .busiest:
            guard let core = snapshot.busiestCore else { return "Measuring CPU usage…" }
            return "\(core.label) is busiest at \(core.percentage)%"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            PreferencesView(preferences: preferences)
                .padding(14)

            Divider()

            visualization
                .padding(14)

            Divider()

            footer
        }
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Open Menu Stats")
                    .font(.headline)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()
        }
        .padding(14)
    }

    @ViewBuilder
    private var visualization: some View {
        if let errorMessage = monitor.errorMessage, monitor.snapshot == nil {
            ContentUnavailableView(
                "CPU data unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
            .frame(height: 150)
        } else if displayedCores.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Measuring CPU usage…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
        } else {
            switch preferences.visualization {
            case .bars:
                CoreBarChart(cores: displayedCores)
            case .numbers:
                CoreNumberGrid(cores: displayedCores)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let errorMessage = monitor.errorMessage {
                Label("CPU update failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(errorMessage)
            } else {
                Label("Updates every second", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(14)
    }
}
