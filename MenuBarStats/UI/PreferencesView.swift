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
        }
        .font(.subheadline)
    }
}
