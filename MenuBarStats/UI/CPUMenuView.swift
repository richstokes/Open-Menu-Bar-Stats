import AppKit
import Foundation
import SwiftUI

struct CPUMenuView: View {
    let monitor: CPUMonitor
    @Bindable var preferences: AppPreferences
    @State private var showsAbout = false

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
        .sheet(isPresented: $showsAbout) {
            AboutView()
        }
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
                Text("Open Menu Bar Stats")
                    .font(.headline)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if preferences.showsThermalState {
                    Label(
                        "Thermal state: \(monitor.thermalState.title)",
                        systemImage: "thermometer.medium"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
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
            } else if preferences.showsMemory, let errorMessage = monitor.memoryErrorMessage {
                Label("Memory update failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(errorMessage)
            } else {
                Label("Updates every second", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("About") {
                showsAbout = true
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(14)
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private static let coffeeURL = URL(
        string: "https://buymeacoffee.com/richstokes"
    )!
    private static let privacyURL = URL(string: "https://appsbyrich.com/privacy")!

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text("Open Menu Bar Stats")
                    .font(.title2.bold())
                Text("Version \(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("A lightweight, open-source system monitor for the macOS menu bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Link(destination: Self.coffeeURL) {
                Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Opens buymeacoffee.com in your browser")

            Link("Privacy Policy", destination: Self.privacyURL)
                .font(.caption)
                .accessibilityHint("Opens the privacy policy in your browser")

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 320)
    }
}
