import SwiftUI

struct CPUStatusLabel: View {
    let monitor: CPUMonitor
    let preferences: AppPreferences

    private var selectedUsage: Double? {
        guard let snapshot = monitor.snapshot else { return nil }
        switch preferences.coreScope {
        case .all:
            return snapshot.clampedOverallUsage
        case .busiest:
            return snapshot.busiestCore?.clampedUsage
        }
    }

    private var chartValues: [Double] {
        guard let snapshot = monitor.snapshot else { return [] }
        switch preferences.coreScope {
        case .all:
            return snapshot.cores.map(\.clampedUsage)
        case .busiest:
            return snapshot.busiestCore.map { [$0.clampedUsage] } ?? []
        }
    }

    private var accessibilityDescription: String {
        guard let snapshot = monitor.snapshot else {
            return monitor.errorMessage == nil ? "CPU usage, measuring" : "CPU usage unavailable"
        }
        let updateStatus = monitor.errorMessage == nil ? "" : ", latest update failed"

        switch preferences.coreScope {
        case .all:
            return "Overall CPU usage, \(snapshot.overallPercentage) percent\(updateStatus)"
        case .busiest:
            guard let core = snapshot.busiestCore else { return "CPU usage, measuring" }
            return "Busiest CPU, \(core.label), \(core.percentage) percent\(updateStatus)"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu")

            switch preferences.visualization {
            case .bars:
                Group {
                    if chartValues.isEmpty {
                        Text("—")
                    } else {
                        CPUStatusBars(values: chartValues)
                    }
                }
                .frame(width: 60, alignment: .leading)
            case .numbers:
                if let selectedUsage {
                    Text(selectedUsage, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                } else {
                    Text("—")
                        .frame(width: 38, alignment: .trailing)
                }
            }

            if monitor.errorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .task {
            await monitor.run()
        }
    }
}

private struct CPUStatusBars: View {
    let values: [Double]

    private var plottedValues: [Double] {
        guard values.count > 10 else { return values }

        return (0..<10).map { bucket in
            let start = bucket * values.count / 10
            let end = (bucket + 1) * values.count / 10
            return values[start..<end].max() ?? 0
        }
    }

    private var barText: String {
        let levels = Array("▁▂▃▄▅▆▇█")
        let values = plottedValues.isEmpty ? [0] : plottedValues

        return String(values.map { usage in
            let clamped = min(max(usage, 0), 1)
            let index = min(Int(clamped * Double(levels.count)), levels.count - 1)
            return levels[index]
        })
    }

    var body: some View {
        Text(barText)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1)
            .fixedSize()
    }
}
