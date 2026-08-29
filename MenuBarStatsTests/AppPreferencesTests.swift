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

    private func withIsolatedDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "MenuBarStatsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated UserDefaults")
        }

        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }
}
