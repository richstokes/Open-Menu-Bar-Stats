import SwiftUI

struct CoreNumberGrid: View {
    let cores: [CPUCoreReading]

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        if cores.count == 1, let core = cores.first {
            VStack(spacing: 4) {
                Text(core.clampedUsage, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(core.label)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 116)
            .accessibilityElement(children: .combine)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(cores) { core in
                        HStack {
                            Text("C\(core.id + 1)")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(core.clampedUsage, format: .percent.precision(.fractionLength(0)))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(core.label)
                        .accessibilityValue("\(core.percentage) percent")
                    }
                }
            }
            .frame(maxHeight: 244)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Numeric CPU usage by core")
        }
    }
}
