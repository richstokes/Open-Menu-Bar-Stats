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

/// Keeps CPU independently reachable while optional metrics share one compact
/// neighboring item. Neither item is rebuilt when preferences or samples change.
@MainActor
final class MetricStatusItemController: NSObject {
    nonisolated static let cpuStatusItemAutosaveName =
        "OpenMenuStats.StatusItem.V13.CPU"
    nonisolated static let optionalStatusItemAutosaveName =
        "OpenMenuStats.StatusItem.V13.Optional"

    private let monitor: CPUMonitor
    private let preferences: AppPreferences
    private let persistsStatusItemState: Bool

    private(set) var cpuHost: MetricStatusItemHost?
    private(set) var optionalHost: MetricStatusItemHost?
    private var hasStarted = false
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

    init(
        monitor: CPUMonitor,
        preferences: AppPreferences,
        persistsStatusItemState: Bool = true
    ) {
        self.monitor = monitor
        self.preferences = preferences
        self.persistsStatusItemState = persistsStatusItemState
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
        popover.performClose(nil)
        activeButton = nil

        removeStatusItems()
        cpuHost = nil
        optionalHost = nil
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
        ensureStatusItems()
        guard let cpuHost, let optionalHost else { return }

        let showsMemory = preferences.showsMemory
        let showsThermalState = preferences.showsThermalState

        let cpuPresentation = makeCPUPresentation()
        cpuHost.update(
            segments: [
                StatusMetricSegmentState(
                    title: cpuPresentation.title,
                    reservedTitle: cpuReservedTitle(),
                    systemImage: cpuPresentation.hasError
                        ? "exclamationmark.triangle.fill"
                        : "cpu",
                    tint: cpuPresentation.hasError ? .orange : .label,
                    usesMonospacedText: preferences.visualization == .bars
                )
            ],
            accessibilityDescription: "CPU usage",
            accessibilityValue: cpuPresentation.accessibilityLabel
        )

        var optionalSegments: [StatusMetricSegmentState] = []
        var optionalAccessibilityValues: [String] = []
        var optionalMetricNames: [String] = []

        if showsMemory, let memoryPresentation = makeMemoryPresentation() {
            optionalSegments.append(
                StatusMetricSegmentState(
                    title: memoryPresentation.title,
                    reservedTitle: memoryReservedTitle(),
                    systemImage: memoryPresentation.hasError
                        ? "exclamationmark.triangle.fill"
                        : "memorychip",
                    tint: memoryPresentation.hasError ? .orange : .label,
                    usesMonospacedText: preferences.visualization == .bars
                )
            )
            optionalAccessibilityValues.append(memoryPresentation.accessibilityLabel)
            optionalMetricNames.append("memory load")
        } else {
            optionalSegments.append(
                StatusMetricSegmentState(
                    title: "",
                    reservedTitle: memoryReservedTitle(),
                    systemImage: "memorychip",
                    tint: .label,
                    usesMonospacedText: preferences.visualization == .bars,
                    isVisible: false
                )
            )
        }

        let thermalState = monitor.thermalState
        optionalSegments.append(
            StatusMetricSegmentState(
                title: thermalState.menuBarTitle ?? "",
                reservedTitle: nil,
                systemImage: thermalState.systemImage,
                tint: thermalState.menuBarTint,
                usesMonospacedText: false,
                isVisible: showsThermalState
            )
        )
        if showsThermalState {
            optionalAccessibilityValues.append(
                "Thermal state, \(thermalState.title.lowercased())"
            )
            optionalMetricNames.append("thermal state")
        }

        optionalHost.update(
            segments: optionalSegments,
            accessibilityDescription: joinedMetricNames(optionalMetricNames),
            accessibilityValue: optionalAccessibilityValues.joined(separator: ". ")
        )

        // AppKit inserts the item revealed later to the left. Reveal the
        // optional group first so its final Thermal segment stays at the far
        // right, with CPU immediately to the group's left.
        optionalHost.setDesiredVisibility(showsMemory || showsThermalState)
        cpuHost.setDesiredVisibility(true)
    }

    private func ensureStatusItems() {
        guard cpuHost == nil else { return }

        // Create these in display-order priority: the optional group first,
        // then CPU, so CPU is placed immediately to its left.
        optionalHost = makeStatusItem(
            autosaveName: Self.optionalStatusItemAutosaveName,
            segments: [
                StatusMetricSegmentDefinition(
                    systemImage: "memorychip",
                    accessibilityDescription: "Memory load"
                ),
                StatusMetricSegmentDefinition(
                    systemImage: monitor.thermalState.systemImage,
                    accessibilityDescription: "Thermal state"
                )
            ],
            contentAlignment: .trailing,
            accessibilityDescription: "Optional system metrics",
            terminatesOnRemoval: false
        )
        cpuHost = makeStatusItem(
            autosaveName: Self.cpuStatusItemAutosaveName,
            segments: [
                StatusMetricSegmentDefinition(
                    systemImage: "cpu",
                    accessibilityDescription: "CPU usage"
                )
            ],
            contentAlignment: .center,
            accessibilityDescription: "CPU usage",
            terminatesOnRemoval: true
        )
    }

    private func cpuReservedTitle() -> String? {
        switch preferences.visualization {
        // Keep the common one- and two-digit range steady. The uncommon 100%
        // value may grow left temporarily rather than leaving a permanent
        // three-digit gap in the menu bar.
        case .numbers: formattedPercentage(0.99)
        case .bars:
            String(repeating: "█", count: maximumCPUBarCount)
        }
    }

    private func memoryReservedTitle() -> String {
        switch preferences.visualization {
        case .numbers: formattedPercentage(0.99)
        case .bars: "█"
        }
    }

    private func joinedMetricNames(_ names: [String]) -> String {
        switch names.count {
        case 0: return "System metrics"
        case 1: return names[0]
        case 2: return names.joined(separator: " and ")
        default:
            let finalName = names.last ?? "system metrics"
            return "\(names.dropLast().joined(separator: ", ")), and \(finalName)"
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
        autosaveName: String?,
        segments: [StatusMetricSegmentDefinition],
        contentAlignment: StatusMetricContentAlignment,
        accessibilityDescription: String,
        terminatesOnRemoval: Bool
    ) -> MetricStatusItemHost {
        precondition(!segments.isEmpty)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if persistsStatusItemState, let autosaveName {
            item.autosaveName = autosaveName
        }
        item.isVisible = false
        if terminatesOnRemoval {
            item.behavior = .terminationOnRemoval
        }
        let contentView = StatusMetricContentView(
            segments: segments,
            alignment: contentAlignment
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
            segments: segments.map {
                StatusMetricSegmentState(
                    title: "—",
                    reservedTitle: nil,
                    systemImage: $0.systemImage,
                    tint: .label,
                    usesMonospacedText: false
                )
            }
        )
        item.length = MetricStatusItemHost.itemLength(
            forContentWidth: contentView.preferredWidth
        )
        return MetricStatusItemHost(statusItem: item, contentView: contentView)
    }

    private func removeStatusItems() {
        for host in [optionalHost, cpuHost].compactMap({ $0 }) {
            if !persistsStatusItemState {
                host.statusItem.autosaveName = nil
            }
            NSStatusBar.system.removeStatusItem(host.statusItem)
        }
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

private struct MetricPresentation {
    let title: String
    let accessibilityLabel: String
    var hasError = false
}

struct StatusMetricSegmentDefinition: Equatable {
    let systemImage: String
    let accessibilityDescription: String
}

struct StatusMetricSegmentState: Equatable {
    let title: String
    let reservedTitle: String?
    let systemImage: String
    let tint: StatusMetricTint
    let usesMonospacedText: Bool
    var isVisible = true
}

enum StatusMetricContentAlignment {
    case leading
    case center
    case trailing
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
    /// AppKit adds menu-bar chrome outside the custom content. Reducing the
    /// requested length keeps neighboring app metrics visually compact while
    /// retaining a six-point hit-area margin on each side.
    static let menuBarChromeReduction: CGFloat = 12

    let statusItem: NSStatusItem
    let contentView: StatusMetricContentView
    private(set) var desiredVisibility = false
    private var lastAccessibilityDescription: String?
    private var lastAccessibilityValue: String?

    init(statusItem: NSStatusItem, contentView: StatusMetricContentView) {
        self.statusItem = statusItem
        self.contentView = contentView
    }

    static func itemLength(forContentWidth contentWidth: CGFloat) -> CGFloat {
        max(1, ceil(contentWidth - menuBarChromeReduction))
    }

    func setDesiredVisibility(_ isVisible: Bool) {
        guard desiredVisibility != isVisible else { return }
        desiredVisibility = isVisible
        statusItem.isVisible = isVisible
    }

    @discardableResult
    func update(
        segments: [StatusMetricSegmentState],
        accessibilityDescription: String,
        accessibilityValue: String
    ) -> Bool {
        let didChangeWidth = contentView.update(segments: segments)
        var didSetLength = false
        if didChangeWidth {
            let nextLength = Self.itemLength(
                forContentWidth: contentView.preferredWidth
            )
            if nextLength.isFinite, nextLength > 0,
                abs(statusItem.length - nextLength) >= 0.5
            {
                statusItem.length = nextLength
                didSetLength = true
            }
        }

        if lastAccessibilityDescription != accessibilityDescription {
            lastAccessibilityDescription = accessibilityDescription
            statusItem.button?.toolTip =
                "Open Menu Bar Stats — \(accessibilityDescription)"
            statusItem.button?.setAccessibilityLabel(
                "Open Menu Bar Stats, \(accessibilityDescription)"
            )
        }

        if lastAccessibilityValue != accessibilityValue {
            lastAccessibilityValue = accessibilityValue
            statusItem.button?.setAccessibilityValue(accessibilityValue)
        }
        return didSetLength
    }
}

/// Intrinsically sizes visible metrics independently of the status-bar button.
/// This avoids feeding the button's current width back into the next measurement.
@MainActor
final class StatusMetricContentView: NSView {
    static let segmentSpacing: CGFloat = 4

    private let stackView = NSStackView()
    private let segmentViews: [StatusMetricSegmentView]
    private var renderState: [StatusMetricSegmentState]?

    var segmentCount: Int { segmentViews.count }

    var visibleSegmentCount: Int {
        segmentViews.filter { !$0.isHidden }.count
    }

    var segmentAccessibilityDescriptions: [String] {
        segmentViews.map(\.metricAccessibilityDescription)
    }

    var visibleSegmentAccessibilityDescriptions: [String] {
        segmentViews.filter { !$0.isHidden }.map(\.metricAccessibilityDescription)
    }

    var spacing: CGFloat { stackView.spacing }

    var actualContentWidth: CGFloat {
        ceil(stackView.fittingSize.width)
    }

    var preferredWidth: CGFloat {
        let visibleSegments = segmentViews.filter { !$0.isHidden }
        let segmentWidth = visibleSegments.reduce(CGFloat.zero) {
            $0 + $1.reservedFittingWidth
        }
        let gaps = CGFloat(max(visibleSegments.count - 1, 0)) * stackView.spacing
        return ceil(segmentWidth + gaps)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: preferredWidth,
            height: ceil(
                max(
                    stackView.fittingSize.height,
                    StatusMetricSegmentView.symbolBoxSize.height
                )
            )
        )
    }

    convenience init(systemImage: String, accessibilityDescription: String) {
        self.init(
            segments: [
                StatusMetricSegmentDefinition(
                    systemImage: systemImage,
                    accessibilityDescription: accessibilityDescription
                )
            ],
            alignment: .center
        )
    }

    init(
        segments: [StatusMetricSegmentDefinition],
        alignment: StatusMetricContentAlignment = .center
    ) {
        precondition(!segments.isEmpty)
        segmentViews = segments.map {
            StatusMetricSegmentView(
                systemImage: $0.systemImage,
                accessibilityDescription: $0.accessibilityDescription,
                showsTitle: true
            )
        }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = Self.segmentSpacing
        stackView.detachesHiddenViews = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        segmentViews.forEach(stackView.addArrangedSubview)
        addSubview(stackView)
        let horizontalConstraint = switch alignment {
        case .leading: stackView.leadingAnchor.constraint(equalTo: leadingAnchor)
        case .center: stackView.centerXAnchor.constraint(equalTo: centerXAnchor)
        case .trailing: stackView.trailingAnchor.constraint(equalTo: trailingAnchor)
        }
        NSLayoutConstraint.activate([
            horizontalConstraint,
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
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
        update(
            segments: [
                StatusMetricSegmentState(
                    title: title,
                    reservedTitle: reservedTitle,
                    systemImage: systemImage,
                    tint: tint,
                    usesMonospacedText: usesMonospacedText
                )
            ]
        )
    }

    @discardableResult
    func update(segments nextState: [StatusMetricSegmentState]) -> Bool {
        precondition(nextState.count == segmentViews.count)
        guard nextState != renderState else { return false }
        let previousWidth = preferredWidth
        renderState = nextState

        for (segment, state) in zip(segmentViews, nextState) {
            segment.title = state.title
            segment.systemImage = state.systemImage
            segment.symbolColor = state.tint.color
            segment.titleColor = .labelColor
            segment.usesMonospacedText = state.usesMonospacedText
            segment.reservedTitle = state.reservedTitle
            segment.isHidden = !state.isVisible
            segment.layoutSubtreeIfNeeded()
        }
        stackView.layoutSubtreeIfNeeded()
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
    static let iconTitleSpacing: CGFloat = 1
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

    var metricAccessibilityDescription: String { accessibilityDescription }

    var reservedFittingWidth: CGFloat {
        ceil(fittingSize.width)
    }

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
            updateTitleWidthConstraint()
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
            updateTypography()
        }
    }

    /// Reserves width inside the title field so unused space cannot leak out
    /// between neighboring status items. Wider exceptional values can grow.
    var reservedTitle: String? {
        didSet {
            guard reservedTitle != oldValue else { return }
            updateTypography()
        }
    }

    var isCompact = false {
        didSet {
            guard isCompact != oldValue else { return }
            spacing = Self.iconTitleSpacing
            updateTypography()
        }
    }

    init(
        systemImage: String,
        accessibilityDescription: String,
        showsTitle: Bool
    ) {
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
        spacing = Self.iconTitleSpacing

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

    private func updateTypography() {
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

        updateTitleWidthConstraint()
    }

    private func updateTitleWidthConstraint() {
        guard let reservedTitle, !titleLabel.isHidden else {
            titleWidthConstraint?.isActive = false
            return
        }

        let width = max(
            fittingWidth(for: reservedTitle),
            fittingWidth(for: titleLabel.stringValue)
        )
        if let titleWidthConstraint {
            titleWidthConstraint.constant = width
            titleWidthConstraint.isActive = true
        } else {
            let constraint = titleLabel.widthAnchor.constraint(equalToConstant: width)
            constraint.isActive = true
            titleWidthConstraint = constraint
        }
    }

    private func fittingWidth(for text: String) -> CGFloat {
        let sizingLabel = NSTextField(labelWithString: text)
        sizingLabel.font = titleLabel.font
        sizingLabel.lineBreakMode = .byClipping
        sizingLabel.usesSingleLineMode = true
        // NSTextField can round one point wider once arranged in a stack view.
        return ceil(sizingLabel.fittingSize.width + 1)
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
