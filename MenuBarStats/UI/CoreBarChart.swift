import SwiftUI

struct CoreBarChart: View {
    let cores: [CPUCoreReading]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if cores.count == 1, let core = cores.first {
            BusiestCoreBar(core: core, reduceMotion: reduceMotion)
        } else {
            AllCoreBarChart(cores: cores, reduceMotion: reduceMotion)
        }
    }
}

private struct AllCoreBarChart: View {
    let cores: [CPUCoreReading]
    let reduceMotion: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing) {
                Text("100%")
                Spacer()
                Text("50%")
                Spacer()
                Text("0%")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(height: 146)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .bottom, spacing: 7) {
                    ForEach(cores) { core in
                        VStack(spacing: 5) {
                            GeometryReader { proxy in
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(.quaternary)

                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(Color.accentColor.gradient)
                                        .frame(height: max(2, proxy.size.height * core.clampedUsage))
                                        .animation(
                                            reduceMotion ? nil : .easeOut(duration: 0.22),
                                            value: core.clampedUsage
                                        )
                                }
                            }
                            .frame(width: 19, height: 126)

                            Text("\(core.id + 1)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(core.label)
                        .accessibilityValue("\(core.percentage) percent")
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .frame(height: 150)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("CPU usage by core")
    }
}

private struct BusiestCoreBar: View {
    let core: CPUCoreReading
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(core.label)
                    .font(.headline)
                Spacer()
                Text(core.clampedUsage, format: .percent.precision(.fractionLength(0)))
                    .font(.title2.weight(.semibold).monospacedDigit())
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.gradient)
                        .frame(width: max(4, proxy.size.width * core.clampedUsage))
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.22),
                            value: core.clampedUsage
                        )
                }
            }
            .frame(height: 22)
        }
        .padding(.vertical, 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(core.label)
        .accessibilityValue("\(core.percentage) percent CPU usage")
    }
}
