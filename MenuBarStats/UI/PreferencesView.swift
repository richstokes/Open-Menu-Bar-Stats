import SwiftUI

struct PreferencesView: View {
    @Bindable var preferences: AppPreferences

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Cores")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Cores", selection: $preferences.coreScope) {
                    ForEach(CoreScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 190)
            }

            HStack {
                Text("Display")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Display", selection: $preferences.visualization) {
                    ForEach(CPUVisualization.allCases) { visualization in
                        Text(visualization.title).tag(visualization)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 190)
            }

            Divider()
                .padding(.vertical, 2)

            Toggle(isOn: $preferences.showsMemory) {
                Label("Memory in menu bar", systemImage: "memorychip")
            }
            .toggleStyle(.switch)

            Toggle(isOn: $preferences.showsThermalState) {
                Label("Thermal state in menu bar", systemImage: "thermometer.medium")
            }
            .toggleStyle(.switch)
            .help("Shows the qualitative thermal condition reported by macOS.")
        }
        .font(.subheadline)
    }
}
