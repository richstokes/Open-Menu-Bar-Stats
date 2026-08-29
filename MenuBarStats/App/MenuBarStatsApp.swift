import SwiftUI

@main
struct MenuBarStatsApp: App {
    @State private var monitor = CPUMonitor()
    @State private var preferences = AppPreferences()

    var body: some Scene {
        MenuBarExtra {
            CPUMenuView(monitor: monitor, preferences: preferences)
        } label: {
            CPUStatusLabel(monitor: monitor, preferences: preferences)
        }
        .menuBarExtraStyle(.window)
    }
}
