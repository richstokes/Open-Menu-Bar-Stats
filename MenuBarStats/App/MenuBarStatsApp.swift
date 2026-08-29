import AppKit
import Observation
import OSLog
import SwiftUI

@main
struct MenuBarStatsApp: App {
    @NSApplicationDelegateAdaptor(MenuBarStatsApplicationDelegate.self)
    private var applicationDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class MenuBarStatsApplicationDelegate: NSObject, NSApplicationDelegate {
    private let monitor = CPUMonitor()
    private let preferences = AppPreferences()
    private var statusItems: MetricStatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItems = MetricStatusItemController(
            monitor: monitor,
            preferences: preferences
        )
        self.statusItems = statusItems
        statusItems.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItems?.stop()
    }
}

/// Owns the optional status items independently of SwiftUI's primary CPU scene.
///
/// `NSStatusItem.autosaveName` is deliberately unique for every metric. AppKit's
/// contract requires apps with multiple status items to name them so macOS can
/// persist each item's position and visibility without conflating their state.
@MainActor
final class MetricStatusItemController: NSObject {
    nonisolated static let cpuAutosaveName = "OpenMenuStats.CPU"
    nonisolated static let memoryAutosaveName = "OpenMenuStats.Memory"
    nonisolated static let thermalAutosaveName = "OpenMenuStats.Thermal"
    private static let logger = Logger(subsystem: "richstokes.menubarstats", category: "StatusItems")

    private let monitor: CPUMonitor
    private let preferences: AppPreferences

    private var cpuStatusItem: NSStatusItem?
    private var memoryStatusItem: NSStatusItem?
    private var thermalStatusItem: NSStatusItem?
    private var hasStarted = false
    private var samplingConfiguration: SamplingConfiguration?
    private var samplingTask: Task<Void, Never>?
    private weak var activeButton: NSStatusBarButton?

    private lazy var popover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: CPUMenuView(monitor: monitor, preferences: preferences)
        )
        return popover
    }()

    init(monitor: CPUMonitor, preferences: AppPreferences) {
        self.monitor = monitor
        self.preferences = preferences
        super.init()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        Self.logger.notice(
            "Starting status items; memory=\(self.preferences.showsMemory), thermal=\(self.preferences.showsThermalState)"
        )

        // Create every item exactly once. Their distinct autosave names remain
        // attached for the entire process; toggles only change visibility.
        cpuStatusItem = makeStatusItem(
            autosaveName: Self.cpuAutosaveName,
            systemImage: "cpu",
            accessibilityDescription: "CPU usage"
        )
        memoryStatusItem = makeStatusItem(
            autosaveName: Self.memoryAutosaveName,
            systemImage: "memorychip",
            accessibilityDescription: "Memory load"
        )
        thermalStatusItem = makeStatusItem(
            autosaveName: Self.thermalAutosaveName,
            systemImage: "thermometer.medium",
            accessibilityDescription: "Thermal state"
        )

        Self.logger.notice(
            "Created independent items; cpuVisible=\(self.cpuStatusItem?.isVisible ?? false), memoryVisible=\(self.memoryStatusItem?.isVisible ?? false), thermalVisible=\(self.thermalStatusItem?.isVisible ?? false)"
        )

        observeAndRefresh()
    }

    func stop() {
        guard hasStarted else { return }
        hasStarted = false
        samplingTask?.cancel()
        samplingTask = nil

        for item in [cpuStatusItem, memoryStatusItem, thermalStatusItem].compactMap({ $0 }) {
            NSStatusBar.system.removeStatusItem(item)
        }

        cpuStatusItem = nil
        memoryStatusItem = nil
        thermalStatusItem = nil
    }

    private func observeAndRefresh() {
        guard hasStarted else { return }

        // Observation callbacks are one-shot. Re-register after each relevant
        // model change and render from the newest state without a polling timer.
        withObservationTracking {
            refresh()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeAndRefresh()
            }
        }
    }

    private func refresh() {
        refreshSamplingTask()
        refreshCPUStatusItem()
        refreshMemoryStatusItem()
        refreshThermalStatusItem()
    }

    private func refreshSamplingTask() {
        let nextConfiguration = SamplingConfiguration(
            samplesMemory: preferences.showsMemory,
            isScreenAwake: monitor.isScreenAwake,
            isSessionActive: monitor.isSessionActive
        )

        guard nextConfiguration != samplingConfiguration else { return }
        samplingConfiguration = nextConfiguration
        samplingTask?.cancel()
        samplingTask = nil

        guard nextConfiguration.isScreenAwake, nextConfiguration.isSessionActive else { return }

        samplingTask = Task(priority: .utility) { [monitor] in
            await monitor.run(samplesMemory: nextConfiguration.samplesMemory)
        }
    }

    private func refreshCPUStatusItem() {
        guard let cpuStatusItem else { return }
        cpuStatusItem.isVisible = true

        guard let button = cpuStatusItem.button else { return }
        guard let snapshot = monitor.snapshot else {
            button.title = "—"
            button.toolTip = "Measuring CPU usage"
            button.setAccessibilityLabel("CPU usage, measuring")
            return
        }

        let selectedUsage: Double
        let accessibilityLabel: String
        let chartValues: [Double]

        switch preferences.coreScope {
        case .all:
            selectedUsage = snapshot.clampedOverallUsage
            accessibilityLabel = "Overall CPU usage, \(snapshot.overallPercentage) percent"
            chartValues = snapshot.cores.map(\.clampedUsage)
        case .busiest:
            guard let core = snapshot.busiestCore else { return }
            selectedUsage = core.clampedUsage
            accessibilityLabel = "Busiest CPU, \(core.label), \(core.percentage) percent"
            chartValues = [core.clampedUsage]
        }

        switch preferences.visualization {
        case .numbers:
            button.title = selectedUsage.formatted(
                .percent.precision(.fractionLength(0))
            )
        case .bars:
            button.title = cpuBarText(values: chartValues)
        }

        button.toolTip = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
    }

    private func refreshMemoryStatusItem() {
        guard let memoryStatusItem else { return }

        guard preferences.showsMemory else {
            closePopoverIfAnchored(to: memoryStatusItem)
            memoryStatusItem.isVisible = false
            return
        }

        memoryStatusItem.isVisible = true
        Self.logger.debug("Refreshed memory item as visible")
        guard let button = memoryStatusItem.button else { return }

        if let snapshot = monitor.memorySnapshot {
            button.title = "\(snapshot.percentage)%"
            button.toolTip = "Memory load: \(snapshot.percentage)%"
            button.setAccessibilityLabel("Memory load, \(snapshot.percentage) percent")
        } else {
            button.title = "—"
            button.toolTip = "Measuring memory load"
            button.setAccessibilityLabel("Memory load, measuring")
        }
    }

    private func refreshThermalStatusItem() {
        guard let thermalStatusItem else { return }

        guard preferences.showsThermalState else {
            closePopoverIfAnchored(to: thermalStatusItem)
            thermalStatusItem.isVisible = false
            return
        }

        thermalStatusItem.isVisible = true
        guard let button = thermalStatusItem.button else { return }

        let state = monitor.thermalState.title
        button.title = state
        button.toolTip = "Thermal state: \(state)"
        button.setAccessibilityLabel("Thermal state, \(state.lowercased())")
    }

    private func makeStatusItem(
        autosaveName: String,
        systemImage: String,
        accessibilityDescription: String
    ) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = autosaveName

        if let button = item.button {
            let image = NSImage(
                systemSymbolName: systemImage,
                accessibilityDescription: accessibilityDescription
            )
            image?.isTemplate = true

            button.image = image
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            button.target = self
            button.action = #selector(statusItemClicked(_:))
        }

        return item
    }

    private func cpuBarText(values: [Double]) -> String {
        let plottedValues: [Double]
        if values.count > 10 {
            plottedValues = (0..<10).map { bucket in
                let start = bucket * values.count / 10
                let end = (bucket + 1) * values.count / 10
                return values[start..<end].max() ?? 0
            }
        } else {
            plottedValues = values
        }

        let levels = Array("▁▂▃▄▅▆▇█")
        return String(plottedValues.map { usage in
            let clamped = min(max(usage, 0), 1)
            let index = min(Int(clamped * Double(levels.count)), levels.count - 1)
            return levels[index]
        })
    }

    private func closePopoverIfAnchored(to item: NSStatusItem) {
        guard activeButton === item.button else { return }
        popover.performClose(nil)
        activeButton = nil
    }

    @objc
    private func statusItemClicked(_ sender: NSStatusBarButton) {
        if popover.isShown, activeButton === sender {
            popover.performClose(nil)
            activeButton = nil
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        }

        activeButton = sender
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }
}

private struct SamplingConfiguration: Equatable {
    let samplesMemory: Bool
    let isScreenAwake: Bool
    let isSessionActive: Bool
}
