import AppKit
import Observation
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

/// Owns one stable status item containing independently toggled metric segments.
///
/// macOS may temporarily suppress individual status items when the right side of
/// the menu bar reaches its reserved center area, while still reporting those
/// items as visible. Keeping the metric symbols in one host prevents Memory and
/// Thermal from appearing to replace each other in a crowded menu bar.
@MainActor
final class MetricStatusItemController: NSObject {
    nonisolated static let statusItemAutosaveName = "OpenMenuStats.StatusItem.V5"

    private let monitor: CPUMonitor
    private let preferences: AppPreferences

    private var statusItem: NSStatusItem?
    private var contentView: StatusItemContentView?
    private var hasStarted = false
    private var samplingConfiguration: SamplingConfiguration?
    private var samplingTask: Task<Void, Never>?

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

        (statusItem, contentView) = makeStatusItem()
        observeAndRefresh()
    }

    func stop() {
        guard hasStarted else { return }
        hasStarted = false
        samplingTask?.cancel()
        samplingTask = nil

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }

        statusItem = nil
        contentView = nil
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
        refreshStatusItem()
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

    private func refreshStatusItem() {
        guard let statusItem, let contentView, let button = statusItem.button else { return }
        statusItem.isVisible = true

        let isCompact = preferences.showsMemory || preferences.showsThermalState
        let cpuPresentation = makeCPUPresentation(isCompact: isCompact)
        let memoryPresentation = makeMemoryPresentation()
        let thermalState = preferences.showsThermalState ? monitor.thermalState : nil

        contentView.update(
            cpuTitle: cpuPresentation.title,
            memoryTitle: memoryPresentation?.title,
            thermalState: thermalState,
            isCompact: isCompact
        )
        statusItem.length = contentView.preferredWidth + 6

        let accessibilityParts = [
            cpuPresentation.accessibilityLabel,
            memoryPresentation?.accessibilityLabel,
            thermalState.map { "Thermal state, \($0.title.lowercased())" }
        ].compactMap { $0 }
        let description = accessibilityParts.joined(separator: ". ")
        button.toolTip = description
        button.setAccessibilityLabel(description)
    }

    private func makeCPUPresentation(isCompact: Bool) -> MetricPresentation {
        guard let snapshot = monitor.snapshot else {
            return MetricPresentation(title: "—", accessibilityLabel: "CPU usage, measuring")
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
            guard let core = snapshot.busiestCore else {
                return MetricPresentation(title: "—", accessibilityLabel: "CPU usage, measuring")
            }
            selectedUsage = core.clampedUsage
            accessibilityLabel = "Busiest CPU, \(core.label), \(core.percentage) percent"
            chartValues = [core.clampedUsage]
        }

        let title: String
        switch preferences.visualization {
        case .numbers:
            if isCompact {
                title = String(Int((selectedUsage * 100).rounded()))
            } else {
                title = selectedUsage.formatted(.percent.precision(.fractionLength(0)))
            }
        case .bars:
            title = cpuBarText(values: chartValues, maximumBars: isCompact ? 4 : 10)
        }

        return MetricPresentation(title: title, accessibilityLabel: accessibilityLabel)
    }

    private func makeMemoryPresentation() -> MetricPresentation? {
        guard preferences.showsMemory else { return nil }

        guard let snapshot = monitor.memorySnapshot else {
            return MetricPresentation(title: "—", accessibilityLabel: "Memory load, measuring")
        }

        return MetricPresentation(
            title: String(snapshot.percentage),
            accessibilityLabel: "Memory load, \(snapshot.percentage) percent"
        )
    }

    private func makeStatusItem() -> (NSStatusItem, StatusItemContentView) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.statusItemAutosaveName
        let contentView = StatusItemContentView()

        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.addSubview(contentView)

            NSLayoutConstraint.activate([
                contentView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 3),
                contentView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -3),
                contentView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
        }

        contentView.update(
            cpuTitle: "—",
            memoryTitle: nil,
            thermalState: nil,
            isCompact: false
        )
        item.length = contentView.preferredWidth + 6
        return (item, contentView)
    }

    private func cpuBarText(values: [Double], maximumBars: Int) -> String {
        let plottedValues: [Double]
        if values.count > maximumBars {
            plottedValues = (0..<maximumBars).map { bucket in
                let start = bucket * values.count / maximumBars
                let end = (bucket + 1) * values.count / maximumBars
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

    @objc
    private func statusItemClicked(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }
}

private struct MetricPresentation {
    let title: String
    let accessibilityLabel: String
}

/// Renders each metric as a distinct symbol inside one status-bar button. The
/// button continues to own clicks, highlighting, accessibility, and anchoring.
@MainActor
private final class StatusItemContentView: NSView {
    private let cpuSegment = StatusMetricSegmentView(
        systemImage: "cpu",
        accessibilityDescription: "CPU usage",
        showsTitle: true
    )
    private let memorySegment = StatusMetricSegmentView(
        systemImage: "memorychip",
        accessibilityDescription: "Memory load",
        showsTitle: true
    )
    private let thermalSegment = StatusMetricSegmentView(
        systemImage: "thermometer.medium",
        accessibilityDescription: "Thermal state",
        showsTitle: false
    )
    private let stackView = NSStackView()

    var preferredWidth: CGFloat {
        ceil(stackView.fittingSize.width)
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 5
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(cpuSegment)
        stackView.addArrangedSubview(memorySegment)
        stackView.addArrangedSubview(thermalSegment)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func update(
        cpuTitle: String,
        memoryTitle: String?,
        thermalState: SystemThermalState?,
        isCompact: Bool
    ) {
        cpuSegment.title = cpuTitle
        memorySegment.title = memoryTitle ?? "—"
        memorySegment.isHidden = memoryTitle == nil
        thermalSegment.isHidden = thermalState == nil

        if let thermalState {
            thermalSegment.systemImage = thermalState.systemImage
        }

        cpuSegment.isCompact = isCompact
        memorySegment.isCompact = isCompact
        thermalSegment.isCompact = isCompact
        stackView.spacing = isCompact ? 4 : 5
        layoutSubtreeIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

@MainActor
private final class StatusMetricSegmentView: NSStackView {
    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let imageWidthConstraint: NSLayoutConstraint
    private let imageHeightConstraint: NSLayoutConstraint
    private let accessibilityDescription: String

    var systemImage: String {
        didSet { updateImage() }
    }

    var title: String {
        get { titleLabel.stringValue }
        set { titleLabel.stringValue = newValue }
    }

    var isCompact = false {
        didSet {
            guard isCompact != oldValue else { return }
            let imageSize: CGFloat = isCompact ? 12 : 16
            imageWidthConstraint.constant = imageSize
            imageHeightConstraint.constant = imageSize
            spacing = isCompact ? 1.5 : 4
            titleLabel.font = isCompact
                ? .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
                : .menuBarFont(ofSize: 0)
        }
    }

    init(systemImage: String, accessibilityDescription: String, showsTitle: Bool) {
        self.systemImage = systemImage
        self.accessibilityDescription = accessibilityDescription
        imageWidthConstraint = imageView.widthAnchor.constraint(equalToConstant: 16)
        imageHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: 16)
        super.init(frame: .zero)
        setAccessibilityElement(false)

        orientation = .horizontal
        alignment = .centerY
        spacing = 4

        updateImage()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .controlTextColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .menuBarFont(ofSize: 0)
        titleLabel.textColor = .controlTextColor
        titleLabel.isHidden = !showsTitle
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        addArrangedSubview(imageView)
        addArrangedSubview(titleLabel)
        NSLayoutConstraint.activate([imageWidthConstraint, imageHeightConstraint])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateImage() {
        let image = NSImage(
            systemSymbolName: systemImage,
            accessibilityDescription: accessibilityDescription
        )
        image?.isTemplate = true
        imageView.image = image
    }
}

private extension SystemThermalState {
    var systemImage: String {
        switch self {
        case .nominal: "thermometer.low"
        case .fair: "thermometer.medium"
        case .serious, .critical: "thermometer.high"
        }
    }
}

private struct SamplingConfiguration: Equatable {
    let samplesMemory: Bool
    let isScreenAwake: Bool
    let isSessionActive: Bool
}
