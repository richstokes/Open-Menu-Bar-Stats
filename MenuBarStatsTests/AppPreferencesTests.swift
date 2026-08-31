import Foundation
import XCTest
@testable import MenuBarStats

final class AppPreferencesTests: XCTestCase {
    func testDefaultsUseAllCoresAndBars() {
        withIsolatedDefaults { defaults in
            let preferences = AppPreferences(defaults: defaults)

            XCTAssertEqual(preferences.coreScope, .all)
            XCTAssertEqual(preferences.visualization, .bars)
            XCTAssertFalse(preferences.showsThermalState)
            XCTAssertFalse(preferences.showsMemory)
        }
    }

    func testSavedPreferencesAreRestored() {
        withIsolatedDefaults { defaults in
            defaults.set(CoreScope.busiest.rawValue, forKey: AppPreferences.Keys.coreScope)
            defaults.set(CPUVisualization.numbers.rawValue, forKey: AppPreferences.Keys.visualization)
            defaults.set(true, forKey: AppPreferences.Keys.showsThermalState)
            defaults.set(true, forKey: AppPreferences.Keys.showsMemory)

            let preferences = AppPreferences(defaults: defaults)

            XCTAssertEqual(preferences.coreScope, .busiest)
            XCTAssertEqual(preferences.visualization, .numbers)
            XCTAssertTrue(preferences.showsThermalState)
            XCTAssertTrue(preferences.showsMemory)
        }
    }

    func testInvalidValuesFallBackSafely() {
        withIsolatedDefaults { defaults in
            defaults.set("not-a-scope", forKey: AppPreferences.Keys.coreScope)
            defaults.set("not-a-visualization", forKey: AppPreferences.Keys.visualization)

            let preferences = AppPreferences(defaults: defaults)

            XCTAssertEqual(preferences.coreScope, .all)
            XCTAssertEqual(preferences.visualization, .bars)
            XCTAssertFalse(preferences.showsThermalState)
            XCTAssertFalse(preferences.showsMemory)
        }
    }

    func testChangesPersistImmediately() {
        withIsolatedDefaults { defaults in
            let preferences = AppPreferences(defaults: defaults)
            preferences.coreScope = .busiest
            preferences.visualization = .numbers
            preferences.showsThermalState = true
            preferences.showsMemory = true

            let restored = AppPreferences(defaults: defaults)

            XCTAssertEqual(restored.coreScope, .busiest)
            XCTAssertEqual(restored.visualization, .numbers)
            XCTAssertTrue(restored.showsThermalState)
            XCTAssertTrue(restored.showsMemory)
        }
    }

    func testMetricVisibilityPreferencesNeverOverwriteEachOther() {
        withIsolatedDefaults { defaults in
            let preferences = AppPreferences(defaults: defaults)

            preferences.showsMemory = true
            XCTAssertTrue(preferences.showsMemory)
            XCTAssertFalse(preferences.showsThermalState)

            preferences.showsThermalState = true
            XCTAssertTrue(preferences.showsMemory)
            XCTAssertTrue(preferences.showsThermalState)

            preferences.showsMemory = false
            XCTAssertFalse(preferences.showsMemory)
            XCTAssertTrue(preferences.showsThermalState)

            preferences.showsMemory = true
            preferences.showsThermalState = false

            let restored = AppPreferences(defaults: defaults)
            XCTAssertTrue(restored.showsMemory)
            XCTAssertFalse(restored.showsThermalState)
        }
    }

    func testPersistentStatusItemsUseDistinctFreshAutosaveNames() {
        XCTAssertEqual(
            MetricStatusItemController.cpuStatusItemAutosaveName,
            "OpenMenuStats.StatusItem.V12.CPU"
        )
        XCTAssertEqual(
            MetricStatusItemController.optionalStatusItemAutosaveName,
            "OpenMenuStats.StatusItem.V12.Optional"
        )
    }

    @MainActor
    func testNumericStatusSegmentKeepsCommonValuesStableAndFits100Percent() throws {
        for isCompact in [false, true] {
            let segment = StatusMetricSegmentView(
                systemImage: "cpu",
                accessibilityDescription: "CPU usage",
                showsTitle: true
            )
            segment.isCompact = isCompact
            segment.reservedTitle = "99%"
            let titleLabel = try XCTUnwrap(
                segment.arrangedSubviews.last as? NSTextField
            )
            let widths = ["1%", "14%", "63%", "99%"].map { title in
                segment.title = title
                segment.layoutSubtreeIfNeeded()
                return segment.reservedFittingWidth
            }

            XCTAssertEqual(
                Set(widths.map { ($0 * 100).rounded() / 100 }).count,
                1,
                "Reserved numeric widths changed: \(widths)"
            )
            XCTAssertEqual(titleLabel.alignment, .left)

            let commonWidth = try XCTUnwrap(widths.first)
            segment.title = "100%"
            segment.layoutSubtreeIfNeeded()
            let expandedWidth = segment.reservedFittingWidth
            XCTAssertGreaterThan(expandedWidth, commonWidth)
            XCTAssertGreaterThanOrEqual(
                expandedWidth,
                ceil(segment.fittingSize.width)
            )

            for title in ["99%", "100%", "99%"] {
                segment.title = title
                segment.layoutSubtreeIfNeeded()
                XCTAssertEqual(
                    segment.reservedFittingWidth,
                    expandedWidth,
                    accuracy: 0.01,
                    "99↔100 must not repeatedly resize the status item"
                )
            }

            segment.reservedTitle = "100%"
            segment.title = "1%"
            segment.layoutSubtreeIfNeeded()
            XCTAssertEqual(
                segment.reservedFittingWidth,
                expandedWidth,
                accuracy: 0.01
            )

            segment.reservedTitle = "99%"
            segment.layoutSubtreeIfNeeded()
            XCTAssertEqual(
                segment.reservedFittingWidth,
                commonWidth,
                accuracy: 0.01,
                "Changing layout mode should reset the observed high-water width"
            )
        }
    }

    @MainActor
    func testCombinedMetricWidthDoesNotChangeAtPercentageDigitBoundaries() {
        let content = StatusMetricContentView(
            segments: [
                StatusMetricSegmentDefinition(
                    systemImage: "cpu",
                    accessibilityDescription: "CPU usage"
                ),
                StatusMetricSegmentDefinition(
                    systemImage: "memorychip",
                    accessibilityDescription: "Memory load"
                )
            ]
        )

        let makeState: (String) -> [StatusMetricSegmentState] = { title in
            [
                StatusMetricSegmentState(
                    title: title,
                    reservedTitle: "100%",
                    systemImage: "cpu",
                    tint: .label,
                    usesMonospacedText: false
                ),
                StatusMetricSegmentState(
                    title: "65%",
                    reservedTitle: "100%",
                    systemImage: "memorychip",
                    tint: .label,
                    usesMonospacedText: false
                )
            ]
        }

        XCTAssertTrue(content.update(segments: makeState("3%")))
        let reservedWidth = content.preferredWidth
        let shortContentWidth = content.actualContentWidth
        XCTAssertLessThan(shortContentWidth, reservedWidth)

        XCTAssertFalse(content.update(segments: makeState("65%")))
        XCTAssertEqual(content.preferredWidth, reservedWidth, accuracy: 0.01)
        XCTAssertGreaterThan(content.actualContentWidth, shortContentWidth)
        XCTAssertLessThanOrEqual(content.actualContentWidth, reservedWidth)
        let mediumContentWidth = content.actualContentWidth

        XCTAssertFalse(content.update(segments: makeState("100%")))
        XCTAssertEqual(content.preferredWidth, reservedWidth, accuracy: 0.01)
        XCTAssertGreaterThan(content.actualContentWidth, mediumContentWidth)
        XCTAssertLessThanOrEqual(content.actualContentWidth, reservedWidth)
    }

    @MainActor
    func testBarStatusSegmentKeepsAConstantWidth() {
        let segment = StatusMetricSegmentView(
            systemImage: "cpu",
            accessibilityDescription: "CPU usage",
            showsTitle: true
        )
        segment.usesMonospacedText = true
        segment.reservedTitle = "██████████"

        for isCompact in [false, true] {
            segment.isCompact = isCompact
            let widths = [
                "—",
                "!",
                "▁▁▁▁▁▁▁▁▁▁",
                "██████████",
                "▁▂▃▄▅▆▇█▁█",
            ].map { title in
                segment.title = title
                segment.layoutSubtreeIfNeeded()
                return segment.reservedFittingWidth
            }

            XCTAssertEqual(
                Set(widths.map { ($0 * 100).rounded() / 100 }).count,
                1,
                "Bar glyphs should not resize the status segment"
            )
        }
    }

    @MainActor
    func testStatusSegmentCanColorItsSymbolWithoutColoringItsTitle() throws {
        let segment = StatusMetricSegmentView(
            systemImage: "thermometer.medium",
            accessibilityDescription: "Thermal state",
            showsTitle: true
        )
        segment.symbolColor = .systemYellow
        segment.titleColor = .labelColor

        let imageView = try XCTUnwrap(segment.arrangedSubviews.first as? NSImageView)
        let titleLabel = try XCTUnwrap(segment.arrangedSubviews.last as? NSTextField)
        XCTAssertEqual(imageView.contentTintColor, .systemYellow)
        XCTAssertEqual(titleLabel.textColor, .labelColor)
    }

    @MainActor
    func testStatusSegmentKeepsAStandardSymbolSizeInEveryLayout() throws {
        let segment = StatusMetricSegmentView(
            systemImage: "cpu",
            accessibilityDescription: "CPU usage",
            showsTitle: true
        )
        let imageView = try XCTUnwrap(segment.arrangedSubviews.first as? NSImageView)
        let expectedSize = StatusMetricSegmentView.symbolBoxSize
        let widthConstraint = try XCTUnwrap(
            imageView.constraints.first { $0.firstAttribute == .width }
        )
        let heightConstraint = try XCTUnwrap(
            imageView.constraints.first { $0.firstAttribute == .height }
        )

        for isCompact in [false, true] {
            segment.isCompact = isCompact

            XCTAssertEqual(widthConstraint.constant, expectedSize.width, accuracy: 0.01)
            XCTAssertEqual(heightConstraint.constant, expectedSize.height, accuracy: 0.01)
            XCTAssertEqual(
                imageView.symbolConfiguration,
                StatusMetricSegmentView.symbolConfiguration
            )
        }
    }

    @MainActor
    func testStatusSegmentWidthIsStableAcrossMenuBarSymbols() {
        let segment = StatusMetricSegmentView(
            systemImage: "cpu",
            accessibilityDescription: "System status",
            showsTitle: true
        )
        segment.title = "42%"

        let widths = [
            "cpu",
            "memorychip",
            "thermometer.medium",
            "exclamationmark.triangle.fill",
        ].map { symbolName in
            segment.systemImage = symbolName
            segment.layoutSubtreeIfNeeded()
            return segment.fittingSize.width
        }

        XCTAssertEqual(Set(widths.map { ($0 * 100).rounded() / 100 }).count, 1)
    }

    @MainActor
    func testMetricContentWidthIsIndependentOfItsContainerFrame() {
        let content = StatusMetricContentView(
            systemImage: "memorychip",
            accessibilityDescription: "Memory load"
        )
        content.update(
            title: "59%",
            reservedTitle: "100%",
            systemImage: "memorychip",
            tint: .label,
            usesMonospacedText: false
        )
        let expectedWidth = content.preferredWidth

        for containerWidth in [1.0, 40.0, 300.0] {
            content.frame.size.width = containerWidth
            content.layoutSubtreeIfNeeded()

            XCTAssertEqual(content.preferredWidth, expectedWidth, accuracy: 0.01)
            XCTAssertEqual(content.intrinsicContentSize.width, expectedWidth, accuracy: 0.01)
        }
    }

    @MainActor
    func testOptionalMetricContentKeepsOrderSpacingAndStableMemoryWidth() {
        let content = StatusMetricContentView(
            segments: [
                StatusMetricSegmentDefinition(
                    systemImage: "memorychip",
                    accessibilityDescription: "Memory load"
                ),
                StatusMetricSegmentDefinition(
                    systemImage: "thermometer.low",
                    accessibilityDescription: "Thermal state"
                ),
            ]
        )
        let initialStates = [
            StatusMetricSegmentState(
                title: "1%",
                reservedTitle: "100%",
                systemImage: "memorychip",
                tint: .label,
                usesMonospacedText: false
            ),
            StatusMetricSegmentState(
                title: "",
                reservedTitle: nil,
                systemImage: "thermometer.low",
                tint: .label,
                usesMonospacedText: false
            ),
        ]

        XCTAssertTrue(content.update(segments: initialStates))
        let width = content.preferredWidth
        XCTAssertEqual(content.segmentCount, 2)
        XCTAssertEqual(
            content.segmentAccessibilityDescriptions,
            ["Memory load", "Thermal state"]
        )
        XCTAssertEqual(content.spacing, StatusMetricContentView.segmentSpacing, accuracy: 0.01)
        XCTAssertEqual(content.spacing, 4, accuracy: 0.01)

        var updatedStates = initialStates
        updatedStates[0] = StatusMetricSegmentState(
            title: "100%",
            reservedTitle: "100%",
            systemImage: "memorychip",
            tint: .label,
            usesMonospacedText: false
        )
        XCTAssertFalse(content.update(segments: updatedStates))
        XCTAssertEqual(content.preferredWidth, width, accuracy: 0.01)
        XCTAssertFalse(content.update(segments: updatedStates))
    }

    @MainActor
    func testHiddenMiddleMetricDetachesWithoutLeavingExtraSpacing() {
        let combined = StatusMetricContentView(
            segments: [
                StatusMetricSegmentDefinition(
                    systemImage: "cpu",
                    accessibilityDescription: "CPU usage"
                ),
                StatusMetricSegmentDefinition(
                    systemImage: "memorychip",
                    accessibilityDescription: "Memory load"
                ),
                StatusMetricSegmentDefinition(
                    systemImage: "thermometer.low",
                    accessibilityDescription: "Thermal state"
                ),
            ]
        )
        let visiblePair = StatusMetricContentView(
            segments: [
                StatusMetricSegmentDefinition(
                    systemImage: "cpu",
                    accessibilityDescription: "CPU usage"
                ),
                StatusMetricSegmentDefinition(
                    systemImage: "thermometer.low",
                    accessibilityDescription: "Thermal state"
                ),
            ]
        )
        let cpu = StatusMetricSegmentState(
            title: "14%",
            reservedTitle: "100%",
            systemImage: "cpu",
            tint: .label,
            usesMonospacedText: false
        )
        let hiddenMemory = StatusMetricSegmentState(
            title: "63%",
            reservedTitle: "100%",
            systemImage: "memorychip",
            tint: .label,
            usesMonospacedText: false,
            isVisible: false
        )
        let thermal = StatusMetricSegmentState(
            title: "",
            reservedTitle: nil,
            systemImage: "thermometer.low",
            tint: .label,
            usesMonospacedText: false
        )

        XCTAssertTrue(combined.update(segments: [cpu, hiddenMemory, thermal]))
        XCTAssertTrue(visiblePair.update(segments: [cpu, thermal]))
        XCTAssertEqual(combined.visibleSegmentCount, 2)
        XCTAssertEqual(
            combined.visibleSegmentAccessibilityDescriptions,
            ["CPU usage", "Thermal state"]
        )
        XCTAssertEqual(combined.preferredWidth, visiblePair.preferredWidth, accuracy: 0.01)
        XCTAssertEqual(combined.actualContentWidth, visiblePair.actualContentWidth, accuracy: 0.01)
    }

    @MainActor
    func testOptionalMetricTogglesKeepPersistentCPUAndOptionalItems() async throws {
        let suiteName = "MenuBarStatsControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let monitor = CPUMonitor()
        let preferences = AppPreferences(defaults: defaults)
        preferences.coreScope = .busiest
        preferences.visualization = .numbers
        let controller = MetricStatusItemController(
            monitor: monitor,
            preferences: preferences,
            persistsStatusItemState: false
        )
        controller.start()
        defer { controller.stop() }

        let initialCPUHost = try XCTUnwrap(controller.cpuHost)
        let initialOptionalHost = try XCTUnwrap(controller.optionalHost)
        let initialCPUStatusItem = initialCPUHost.statusItem
        let initialOptionalStatusItem = initialOptionalHost.statusItem
        let cpuLength = initialCPUHost.statusItem.length

        XCTAssertEqual(initialCPUHost.contentView.segmentCount, 1)
        XCTAssertEqual(initialCPUHost.contentView.visibleSegmentCount, 1)
        XCTAssertEqual(
            initialCPUHost.contentView.visibleSegmentAccessibilityDescriptions,
            ["CPU usage"]
        )
        XCTAssertTrue(initialCPUHost.desiredVisibility)
        XCTAssertTrue(initialCPUHost.statusItem.isVisible)
        XCTAssertTrue(initialCPUHost.statusItem.behavior.contains(.terminationOnRemoval))
        XCTAssertEqual(
            initialCPUHost.statusItem.button?.toolTip,
            "Open Menu Bar Stats — CPU usage"
        )
        XCTAssertTrue(initialCPUHost.statusItem.button?.target === controller)
        XCTAssertEqual(
            initialCPUHost.statusItem.button?.action,
            NSSelectorFromString("statusItemClicked:")
        )
        assertValidLength(of: initialCPUHost)
        XCTAssertEqual(initialOptionalHost.contentView.segmentCount, 2)
        XCTAssertEqual(initialOptionalHost.contentView.visibleSegmentCount, 0)
        XCTAssertFalse(initialOptionalHost.desiredVisibility)
        XCTAssertFalse(initialOptionalHost.statusItem.isVisible)
        XCTAssertFalse(
            initialOptionalHost.statusItem.behavior.contains(.terminationOnRemoval)
        )

        preferences.showsMemory = true
        try await waitUntil {
            controller.optionalHost?.desiredVisibility == true
                && controller.optionalHost?.contentView.visibleSegmentCount == 1
        }
        let memoryCPUHost = try XCTUnwrap(controller.cpuHost)
        let memoryHost = try XCTUnwrap(controller.optionalHost)
        XCTAssertTrue(memoryCPUHost === initialCPUHost)
        XCTAssertTrue(memoryCPUHost.statusItem === initialCPUStatusItem)
        XCTAssertEqual(memoryCPUHost.statusItem.length, cpuLength, accuracy: 0.01)
        XCTAssertTrue(memoryHost === initialOptionalHost)
        XCTAssertTrue(memoryHost.statusItem === initialOptionalStatusItem)
        XCTAssertTrue(memoryHost.statusItem.isVisible)
        XCTAssertEqual(
            memoryHost.contentView.visibleSegmentAccessibilityDescriptions,
            ["Memory load"]
        )
        XCTAssertEqual(
            memoryHost.statusItem.button?.toolTip,
            "Open Menu Bar Stats — memory load"
        )
        assertValidLength(of: memoryCPUHost)
        assertValidLength(of: memoryHost)

        preferences.showsThermalState = true
        try await waitUntil {
            controller.optionalHost?.contentView.visibleSegmentCount == 2
        }
        let combinedHost = try XCTUnwrap(controller.optionalHost)
        XCTAssertTrue(combinedHost === initialOptionalHost)
        XCTAssertTrue(combinedHost.statusItem === initialOptionalStatusItem)
        XCTAssertTrue(combinedHost.desiredVisibility)
        XCTAssertTrue(combinedHost.statusItem.isVisible)
        XCTAssertEqual(
            combinedHost.contentView.visibleSegmentAccessibilityDescriptions,
            ["Memory load", "Thermal state"]
        )
        XCTAssertEqual(combinedHost.contentView.spacing, 4, accuracy: 0.01)
        XCTAssertEqual(
            combinedHost.statusItem.button?.toolTip,
            "Open Menu Bar Stats — memory load and thermal state"
        )
        XCTAssertTrue(combinedHost.statusItem.button?.target === controller)
        XCTAssertEqual(
            combinedHost.statusItem.button?.action,
            NSSelectorFromString("statusItemClicked:")
        )
        assertValidLength(of: combinedHost)
        assertCPUIsVisibleAndTerminates(initialCPUHost)
        XCTAssertEqual(initialCPUHost.statusItem.length, cpuLength, accuracy: 0.01)

        preferences.showsMemory = false
        try await waitUntil {
            controller.optionalHost?.contentView.visibleSegmentAccessibilityDescriptions
                == ["Thermal state"]
        }
        let thermalHost = try XCTUnwrap(controller.optionalHost)
        XCTAssertTrue(thermalHost === initialOptionalHost)
        XCTAssertTrue(thermalHost.statusItem === initialOptionalStatusItem)
        XCTAssertEqual(
            thermalHost.statusItem.button?.toolTip,
            "Open Menu Bar Stats — thermal state"
        )
        XCTAssertTrue(thermalHost.statusItem.isVisible)
        assertCPUIsVisibleAndTerminates(initialCPUHost)

        preferences.showsThermalState = false
        try await waitUntil {
            controller.optionalHost?.desiredVisibility == false
        }
        let cpuOnlyHost = try XCTUnwrap(controller.cpuHost)
        let hiddenOptionalHost = try XCTUnwrap(controller.optionalHost)
        XCTAssertTrue(cpuOnlyHost === initialCPUHost)
        XCTAssertTrue(cpuOnlyHost.statusItem === initialCPUStatusItem)
        assertCPUIsVisibleAndTerminates(cpuOnlyHost)
        XCTAssertEqual(cpuOnlyHost.statusItem.length, cpuLength, accuracy: 0.01)
        XCTAssertTrue(hiddenOptionalHost === initialOptionalHost)
        XCTAssertTrue(hiddenOptionalHost.statusItem === initialOptionalStatusItem)
        XCTAssertFalse(hiddenOptionalHost.statusItem.isVisible)
        XCTAssertEqual(hiddenOptionalHost.contentView.visibleSegmentCount, 0)

        preferences.showsMemory = true
        preferences.showsThermalState = true
        try await waitUntil {
            controller.optionalHost?.contentView.visibleSegmentCount == 2
                && controller.optionalHost?.desiredVisibility == true
        }
        let restoredHost = try XCTUnwrap(controller.optionalHost)
        XCTAssertTrue(restoredHost === initialOptionalHost)
        XCTAssertTrue(restoredHost.statusItem === initialOptionalStatusItem)
        XCTAssertTrue(restoredHost.statusItem.isVisible)
        assertCPUIsVisibleAndTerminates(initialCPUHost)
    }

    @MainActor
    func testStatusItemControllerCanRestartSampling() async throws {
        let suiteName = "MenuBarStatsControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let monitor = CPUMonitor()
        let preferences = AppPreferences(defaults: defaults)
        let controller = MetricStatusItemController(
            monitor: monitor,
            preferences: preferences,
            persistsStatusItemState: false
        )

        controller.start()
        try await waitUntil { monitor.isRunning }
        controller.stop()
        try await waitUntil { !monitor.isRunning }

        controller.start()
        try await waitUntil { monitor.isRunning }
        controller.stop()
        try await waitUntil { !monitor.isRunning }
    }

    private func withIsolatedDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "MenuBarStatsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated UserDefaults")
        }

        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }

    @MainActor
    private func assertValidLength(
        of host: MetricStatusItemHost,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let length = host.statusItem.length
        XCTAssertTrue(length.isFinite, file: file, line: line)
        XCTAssertGreaterThan(length, 0, file: file, line: line)
        XCTAssertLessThan(length, 240, file: file, line: line)
        XCTAssertEqual(
            length,
            MetricStatusItemHost.itemLength(
                forContentWidth: host.contentView.preferredWidth
            ),
            accuracy: 0.01,
            file: file,
            line: line
        )
    }

    @MainActor
    private func assertCPUIsVisibleAndTerminates(
        _ host: MetricStatusItemHost,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(host.desiredVisibility, file: file, line: line)
        XCTAssertTrue(host.statusItem.isVisible, file: file, line: line)
        XCTAssertTrue(
            host.statusItem.behavior.contains(.terminationOnRemoval),
            file: file,
            line: line
        )
        assertValidLength(of: host, file: file, line: line)
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(condition())
    }
}
