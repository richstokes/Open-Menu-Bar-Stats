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

    @MainActor
    func testNumericStatusSegmentKeepsAConstantWidth() {
        let segment = StatusMetricSegmentView(
            systemImage: "cpu",
            accessibilityDescription: "CPU usage",
            showsTitle: true
        )
        segment.isCompact = true
        segment.reservedTitle = "100%"

        let widths = ["1%", "27%", "88%", "100%"].map { title in
            segment.title = title
            segment.layoutSubtreeIfNeeded()
            return segment.fittingSize.width
        }

        XCTAssertEqual(Set(widths.map { ($0 * 100).rounded() / 100 }).count, 1)
    }

    @MainActor
    func testBarStatusSegmentKeepsAConstantWidth() {
        let segment = StatusMetricSegmentView(
            systemImage: "cpu",
            accessibilityDescription: "CPU usage",
            showsTitle: true
        )
        segment.usesMonospacedText = true

        for isCompact in [false, true] {
            segment.isCompact = isCompact
            let widths = [
                "▁▁▁▁▁▁▁▁▁▁",
                "██████████",
                "▁▂▃▄▅▆▇█▁█",
            ].map { title in
                segment.title = title
                segment.layoutSubtreeIfNeeded()
                return segment.fittingSize.width
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
    func testStatusItemControllerCanRestartSampling() async throws {
        let suiteName = "MenuBarStatsControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let monitor = CPUMonitor()
        let preferences = AppPreferences(defaults: defaults)
        let controller = MetricStatusItemController(
            monitor: monitor,
            preferences: preferences
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
