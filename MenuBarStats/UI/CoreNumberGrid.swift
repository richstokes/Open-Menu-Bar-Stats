import SwiftUI

struct CoreNumberGrid: View {
    let cores: [CPUCoreReading]

    private let rowHeight: CGFloat = 38
    private let rowSpacing: CGFloat = 8
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private var gridHeight: CGFloat {
        let rowCount = (cores.count + columns.count - 1) / columns.count
        let contentHeight = CGFloat(rowCount) * rowHeight
            + CGFloat(max(0, rowCount - 1)) * rowSpacing
        return min(contentHeight, 244)
    }

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
                LazyVGrid(columns: columns, spacing: rowSpacing) {
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
                        .frame(height: rowHeight)
                        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(core.label)
                        .accessibilityValue("\(core.percentage) percent")
                    }
                }
            }
            // A maximum alone lets the popover collapse the scroll viewport.
            .frame(height: gridHeight)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Numeric CPU usage by core")
        }
    }
}
