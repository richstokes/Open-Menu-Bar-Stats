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

/// Owns independently sized status items for each enabled metric.
///
/// macOS may suppress items at the left edge of a crowded menu bar while still
/// reporting them as visible. Disabled metrics are not kept as hidden hosted
/// scenes, and the visible set is rebuilt with CPU last so the primary metric
/// receives the resilient rightmost placement.
@MainActor
final class MetricStatusItemController: NSObject {
    nonisolated static let statusItemAutosaveName = "OpenMenuStats.StatusItem.V8.CPU"
    nonisolated static let memoryStatusItemAutosaveName =
        "OpenMenuStats.StatusItem.V8.Memory"
    nonisolated static let thermalStatusItemAutosaveName =
        "OpenMenuStats.StatusItem.V8.Thermal"

    private let monitor: CPUMonitor
    private let preferences: AppPreferences

    private(set) var cpuHost: MetricStatusItemHost?
    private(set) var memoryHost: MetricStatusItemHost?
    private(set) var thermalHost: MetricStatusItemHost?
    private var hasStarted = false
    private var statusItemConfiguration: StatusItemConfiguration?
    private var samplingConfiguration: SamplingConfiguration?
    private var samplingTask: Task<Void, Never>?
    private var observationGeneration: UInt64 = 0
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
        observationGeneration &+= 1

        observeAndRefresh(generation: observationGeneration)
    }

    func stop() {
        guard hasStarted else { return }
        hasStarted = false
        observationGeneration &+= 1
        samplingTask?.cancel()
        samplingTask = nil
        samplingConfiguration = nil
        statusItemConfiguration = nil
        popover.performClose(nil)
        activeButton = nil

        for host in [cpuHost, memoryHost, thermalHost].compactMap({ $0 }) {
            NSStatusBar.system.removeStatusItem(host.statusItem)
        }

        cpuHost = nil
        memoryHost = nil
        thermalHost = nil
    }

    private func observeAndRefresh(generation: UInt64) {
        guard hasStarted, generation == observationGeneration else { return }

        // Observation callbacks are one-shot. Re-register after each relevant
        // model change and render from the newest state without a polling timer.
        withObservationTracking {
            refresh()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeAndRefresh(generation: generation)
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

        let previousConfiguration = samplingConfiguration
        guard nextConfiguration != previousConfiguration else { return }
        samplingConfiguration = nextConfiguration
        samplingTask?.cancel()
        samplingTask = nil

        guard nextConfiguration.isScreenAwake, nextConfiguration.isSessionActive else { return }

        let previousRunWasActive = previousConfiguration.map {
            $0.isScreenAwake && $0.isSessionActive
        } ?? false
        let shouldResetCPUBaseline = !previousRunWasActive

        samplingTask = Task(priority: .utility) { [monitor] in
            await monitor.run(
                samplesMemory: nextConfiguration.samplesMemory,
                resetCPUBaseline: shouldResetCPUBaseline
            )
        }
    }

    private func refreshStatusItem() {
        let nextConfiguration = StatusItemConfiguration(
            showsMemory: preferences.showsMemory,
            showsThermalState: preferences.showsThermalState
        )
        if statusItemConfiguration != nextConfiguration {
            rebuildStatusItems(for: nextConfiguration)
        }
        guard let cpuHost else { return }

        let cpuPresentation = makeCPUPresentation()
        cpuHost.update(
            title: cpuPresentation.title,
            reservedTitle: cpuReservedTitle(),
            systemImage: cpuPresentation.hasError ? "exclamationmark.triangle.fill" : "cpu",
            tint: cpuPresentation.hasError ? .orange : .label,
            usesMonospacedText: preferences.visualization == .bars,
            accessibilityValue: cpuPresentation.accessibilityLabel
        )

        if let memoryHost, let memoryPresentation = makeMemoryPresentation() {
            memoryHost.update(
                title: memoryPresentation.title,
                reservedTitle: memoryReservedTitle(),
                systemImage: memoryPresentation.hasError
                    ? "exclamationmark.triangle.fill"
                    : "memorychip",
                tint: memoryPresentation.hasError ? .orange : .label,
                usesMonospacedText: preferences.visualization == .bars,
                accessibilityValue: memoryPresentation.accessibilityLabel
            )
            memoryHost.setDesiredVisibility(true)
        }

        if let thermalHost {
            let thermalState = monitor.thermalState
            thermalHost.update(
                title: thermalState.menuBarTitle ?? "",
                reservedTitle: nil,
                systemImage: thermalState.systemImage,
                tint: thermalState.menuBarTint,
                usesMonospacedText: false,
                accessibilityValue: "Thermal state, \(thermalState.title.lowercased())"
            )
            thermalHost.setDesiredVisibility(true)
        }

        // Reveal CPU last on first launch; subsequent refreshes are a no-op.
        cpuHost.setDesiredVisibility(true)
    }

    private func rebuildStatusItems(for configuration: StatusItemConfiguration) {
        popover.performClose(nil)
        activeButton = nil

        for host in [cpuHost, memoryHost, thermalHost].compactMap({ $0 }) {
            NSStatusBar.system.removeStatusItem(host.statusItem)
        }
        cpuHost = nil
        memoryHost = nil
        thermalHost = nil

        // Later-created items are placed nearer the system menu-bar area. Keep
        // optional metrics to the left and create CPU last so it degrades best
        // when the notch or other status items leave limited room.
        if configuration.showsThermalState {
            thermalHost = makeStatusItem(
                autosaveName: Self.thermalStatusItemAutosaveName,
                systemImage: "thermometer.medium",
                accessibilityDescription: "Thermal state",
                terminatesOnRemoval: false
            )
        }
        if configuration.showsMemory {
            memoryHost = makeStatusItem(
                autosaveName: Self.memoryStatusItemAutosaveName,
                systemImage: "memorychip",
                accessibilityDescription: "Memory load",
                terminatesOnRemoval: false
            )
        }
        cpuHost = makeStatusItem(
            autosaveName: Self.statusItemAutosaveName,
            systemImage: "cpu",
            accessibilityDescription: "CPU usage",
            terminatesOnRemoval: true
        )
        statusItemConfiguration = configuration
    }

    private func cpuReservedTitle() -> String? {
        switch preferences.visualization {
        case .numbers:
            formattedPercentage(1)
        case .bars:
            String(repeating: "█", count: maximumCPUBarCount)
        }
    }

    private func memoryReservedTitle() -> String {
        switch preferences.visualization {
        case .numbers: formattedPercentage(1)
        case .bars: "█"
        }
    }

    private var maximumCPUBarCount: Int {
        switch preferences.coreScope {
        case .all:
            min(
                max(
                    monitor.snapshot?.cores.count
                        ?? ProcessInfo.processInfo.activeProcessorCount,
                    1
                ),
                10
            )
        case .busiest:
            1
        }
    }

    private func makeCPUPresentation() -> MetricPresentation {
        let errorMessage = monitor.errorMessage
        guard let snapshot = monitor.snapshot else {
            if let errorMessage {
                return MetricPresentation(
                    title: "!",
                    accessibilityLabel: "CPU data unavailable: \(errorMessage)",
                    hasError: true
                )
            }
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
            title = formattedPercentage(selectedUsage)
        case .bars:
            title = usageBarText(values: chartValues, maximumBars: maximumCPUBarCount)
        }

        let currentAccessibilityLabel = if let errorMessage {
            "\(accessibilityLabel). Latest CPU update failed: \(errorMessage)"
        } else {
            accessibilityLabel
        }
        return MetricPresentation(
            title: title,
            accessibilityLabel: currentAccessibilityLabel,
            hasError: errorMessage != nil
        )
    }

    private func makeMemoryPresentation() -> MetricPresentation? {
        guard preferences.showsMemory else { return nil }

        let errorMessage = monitor.memoryErrorMessage
        guard let snapshot = monitor.memorySnapshot else {
            if let errorMessage {
                return MetricPresentation(
                    title: "!",
                    accessibilityLabel: "Memory data unavailable: \(errorMessage)",
                    hasError: true
                )
            }
            return MetricPresentation(title: "—", accessibilityLabel: "Memory load, measuring")
        }

        let accessibilityLabel = if let errorMessage {
            "Memory load, \(snapshot.percentage) percent. Latest memory update failed: \(errorMessage)"
        } else {
            "Memory load, \(snapshot.percentage) percent"
        }
        let title = switch preferences.visualization {
        case .numbers: formattedPercentage(snapshot.clampedUsage)
        case .bars: usageBarText(values: [snapshot.clampedUsage], maximumBars: 1)
        }
        return MetricPresentation(
            title: title,
            accessibilityLabel: accessibilityLabel,
            hasError: errorMessage != nil
        )
    }

    private func formattedPercentage(_ usage: Double) -> String {
        usage.formatted(.percent.precision(.fractionLength(0)))
    }

    private func makeStatusItem(
        autosaveName: String,
        systemImage: String,
        accessibilityDescription: String,
        terminatesOnRemoval: Bool
    ) -> MetricStatusItemHost {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = autosaveName
        item.isVisible = false
        if terminatesOnRemoval {
            item.behavior = .terminationOnRemoval
        }
        let contentView = StatusMetricContentView(
            systemImage: systemImage,
            accessibilityDescription: accessibilityDescription
        )

        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.toolTip = "Open Menu Bar Stats — \(accessibilityDescription)"
            button.setAccessibilityLabel(
                "Open Menu Bar Stats, \(accessibilityDescription)"
            )
            button.addSubview(contentView)

            NSLayoutConstraint.activate([
                contentView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                contentView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
        }

        contentView.update(
            title: "—",
            reservedTitle: nil,
            systemImage: systemImage,
            tint: .label,
            usesMonospacedText: false
        )
        item.length = contentView.preferredWidth + 6
        return MetricStatusItemHost(statusItem: item, contentView: contentView)
    }

    private func usageBarText(values: [Double], maximumBars: Int) -> String {
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
        if popover.isShown, activeButton === sender {
            popover.performClose(nil)
            activeButton = nil
            return
        }

        activeButton = sender
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

}

private struct StatusItemConfiguration: Equatable {
    let showsMemory: Bool
    let showsThermalState: Bool
}

private struct MetricPresentation {
    let title: String
    let accessibilityLabel: String
    var hasError = false
}

enum StatusMetricTint: Equatable {
    case label
    case secondary
    case yellow
    case orange
    case red

    var color: NSColor {
        switch self {
        case .label: .labelColor
        case .secondary: .secondaryLabelColor
        case .yellow: .systemYellow
        case .orange: .systemOrange
        case .red: .systemRed
        }
    }
}

/// Keeps a status item and its view stable while its metric is enabled. Width,
/// visibility, and accessibility are only written when genuinely changed.
@MainActor
final class MetricStatusItemHost {
    let statusItem: NSStatusItem
    let contentView: StatusMetricContentView
    private(set) var desiredVisibility = false
    private var lastAccessibilityValue: String?

    init(statusItem: NSStatusItem, contentView: StatusMetricContentView) {
        self.statusItem = statusItem
        self.contentView = contentView
    }

    func setDesiredVisibility(_ isVisible: Bool) {
        guard desiredVisibility != isVisible else { return }
        desiredVisibility = isVisible
        statusItem.isVisible = isVisible
    }

    func update(
        title: String,
        reservedTitle: String?,
        systemImage: String,
        tint: StatusMetricTint,
        usesMonospacedText: Bool,
        accessibilityValue: String
    ) {
        let didChangeWidth = contentView.update(
            title: title,
            reservedTitle: reservedTitle,
            systemImage: systemImage,
            tint: tint,
            usesMonospacedText: usesMonospacedText
        )
        if didChangeWidth {
            let nextLength = contentView.preferredWidth + 6
            if nextLength.isFinite, nextLength > 6,
                abs(statusItem.length - nextLength) >= 0.5
            {
                statusItem.length = nextLength
            }
        }

        if lastAccessibilityValue != accessibilityValue {
            lastAccessibilityValue = accessibilityValue
            statusItem.button?.setAccessibilityValue(accessibilityValue)
        }
    }
}

/// Intrinsically sizes one metric independently of its status-bar button. This
/// avoids feeding the button's current width back into the next width measurement.
@MainActor
final class StatusMetricContentView: NSView {
    private struct RenderState: Equatable {
        let title: String
        let reservedTitle: String?
        let systemImage: String
        let tint: StatusMetricTint
        let usesMonospacedText: Bool
    }

    private let segment: StatusMetricSegmentView
    private var renderState: RenderState?

    var preferredWidth: CGFloat {
        ceil(segment.fittingSize.width)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: preferredWidth,
            height: ceil(
                max(
                    segment.fittingSize.height,
                    StatusMetricSegmentView.symbolBoxSize.height
                )
            )
        )
    }

    init(systemImage: String, accessibilityDescription: String) {
        segment = StatusMetricSegmentView(
            systemImage: systemImage,
            accessibilityDescription: accessibilityDescription,
            showsTitle: true
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)

        segment.translatesAutoresizingMaskIntoConstraints = false
        addSubview(segment)
        NSLayoutConstraint.activate([
            segment.centerXAnchor.constraint(equalTo: centerXAnchor),
            segment.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @discardableResult
    func update(
        title: String,
        reservedTitle: String?,
        systemImage: String,
        tint: StatusMetricTint,
        usesMonospacedText: Bool
    ) -> Bool {
        let nextState = RenderState(
            title: title,
            reservedTitle: reservedTitle,
            systemImage: systemImage,
            tint: tint,
            usesMonospacedText: usesMonospacedText
        )
        guard nextState != renderState else { return false }
        let previousWidth = preferredWidth
        renderState = nextState

        segment.title = title
        segment.systemImage = systemImage
        segment.symbolColor = tint.color
        segment.titleColor = .labelColor
        segment.usesMonospacedText = usesMonospacedText
        segment.reservedTitle = reservedTitle
        segment.layoutSubtreeIfNeeded()
        invalidateIntrinsicContentSize()
        return abs(preferredWidth - previousWidth) >= 0.5
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
final class StatusMetricSegmentView: NSStackView {
    static let symbolBoxSize = NSSize(width: 20, height: 18)
    static let symbolConfiguration = NSImage.SymbolConfiguration(
        pointSize: NSFont.menuBarFont(ofSize: 0).pointSize,
        weight: .regular,
        scale: .large
    )

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let imageWidthConstraint: NSLayoutConstraint
    private let imageHeightConstraint: NSLayoutConstraint
    private let accessibilityDescription: String
    private let supportsTitle: Bool
    private var titleWidthConstraint: NSLayoutConstraint?

    var systemImage: String {
        didSet {
            guard systemImage != oldValue else { return }
            updateImage()
        }
    }

    var title: String {
        get { titleLabel.stringValue }
        set {
            let shouldHide = !supportsTitle || newValue.isEmpty
            guard titleLabel.stringValue != newValue || titleLabel.isHidden != shouldHide else {
                return
            }
            titleLabel.stringValue = newValue
            titleLabel.isHidden = shouldHide
        }
    }

    var symbolColor: NSColor = .labelColor {
        didSet {
            guard symbolColor != oldValue else { return }
            imageView.contentTintColor = symbolColor
        }
    }

    var titleColor: NSColor = .labelColor {
        didSet {
            guard titleColor != oldValue else { return }
            titleLabel.textColor = titleColor
        }
    }

    /// Uses equal-width glyph advances for bar visualizations so their changing
    /// block characters cannot resize the status item on every sample.
    var usesMonospacedText = false {
        didSet {
            guard usesMonospacedText != oldValue else { return }
            updateTypographyAndReservedWidth()
        }
    }

    /// Reserves enough horizontal space for the widest numeric value so live
    /// sampling changes text without moving this or any neighboring segment.
    var reservedTitle: String? {
        didSet {
            guard reservedTitle != oldValue else { return }
            updateTypographyAndReservedWidth()
        }
    }

    var isCompact = false {
        didSet {
            guard isCompact != oldValue else { return }
            spacing = isCompact ? 2.5 : 4
            updateTypographyAndReservedWidth()
        }
    }

    init(systemImage: String, accessibilityDescription: String, showsTitle: Bool) {
        self.systemImage = systemImage
        self.accessibilityDescription = accessibilityDescription
        supportsTitle = showsTitle
        imageWidthConstraint = imageView.widthAnchor.constraint(
            equalToConstant: Self.symbolBoxSize.width
        )
        imageHeightConstraint = imageView.heightAnchor.constraint(
            equalToConstant: Self.symbolBoxSize.height
        )
        super.init(frame: .zero)
        setAccessibilityElement(false)

        orientation = .horizontal
        alignment = .centerY
        spacing = 4

        updateImage()
        imageView.symbolConfiguration = Self.symbolConfiguration
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .menuBarFont(ofSize: 0)
        titleLabel.textColor = .labelColor
        titleLabel.isHidden = !showsTitle
        titleLabel.alignment = .right
        titleLabel.lineBreakMode = .byClipping
        titleLabel.usesSingleLineMode = true
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

    private func updateTypographyAndReservedWidth() {
        let pointSize = isCompact ? 12 : NSFont.menuBarFont(ofSize: 0).pointSize
        let font: NSFont
        if usesMonospacedText {
            font = .monospacedSystemFont(
                ofSize: pointSize,
                weight: isCompact ? .medium : .regular
            )
        } else if reservedTitle != nil {
            font = .monospacedDigitSystemFont(
                ofSize: pointSize,
                weight: isCompact ? .medium : .regular
            )
        } else {
            font = isCompact
                ? .systemFont(ofSize: pointSize, weight: .medium)
                : .menuBarFont(ofSize: 0)
        }
        titleLabel.font = font

        guard let reservedTitle else {
            titleWidthConstraint?.isActive = false
            return
        }

        let reservedWidth = ceil(
            (reservedTitle as NSString).size(withAttributes: [.font: font]).width
        )
        if let titleWidthConstraint {
            titleWidthConstraint.constant = reservedWidth
            titleWidthConstraint.isActive = true
        } else {
            let constraint = titleLabel.widthAnchor.constraint(equalToConstant: reservedWidth)
            constraint.isActive = true
            titleWidthConstraint = constraint
        }
    }
}

private extension SystemThermalState {
    var systemImage: String {
        switch self {
        case .nominal: "thermometer.low"
        case .fair: "thermometer.medium"
        case .serious, .critical: "thermometer.high"
        case .unknown: "thermometer.medium"
        }
    }

    var menuBarTint: StatusMetricTint {
        switch self {
        case .nominal: .label
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        case .unknown: .secondary
        }
    }
}

private struct SamplingConfiguration: Equatable {
    let samplesMemory: Bool
    let isScreenAwake: Bool
    let isSessionActive: Bool
}
