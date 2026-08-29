import Foundation
import XCTest
@testable import MenuBarStats

final class AppPreferencesTests: XCTestCase {
    func testDefaultsUseAllCoresAndBars() {
        withIsolatedDefaults { defaults in
            let preferences = AppPreferences(defaults: defaults)

            XCTAssertEqual(preferences.coreScope, .all)
            XCTAssertEqual(preferences.visualization, .bars)
        }
    }

    func testSavedPreferencesAreRestored() {
        withIsolatedDefaults { defaults in
            defaults.set(CoreScope.busiest.rawValue, forKey: AppPreferences.Keys.coreScope)
            defaults.set(CPUVisualization.numbers.rawValue, forKey: AppPreferences.Keys.visualization)

            let preferences = AppPreferences(defaults: defaults)

            XCTAssertEqual(preferences.coreScope, .busiest)
            XCTAssertEqual(preferences.visualization, .numbers)
        }
    }

    func testInvalidValuesFallBackSafely() {
        withIsolatedDefaults { defaults in
            defaults.set("not-a-scope", forKey: AppPreferences.Keys.coreScope)
            defaults.set("not-a-visualization", forKey: AppPreferences.Keys.visualization)

            let preferences = AppPreferences(defaults: defaults)

            XCTAssertEqual(preferences.coreScope, .all)
            XCTAssertEqual(preferences.visualization, .bars)
        }
    }

    func testChangesPersistImmediately() {
        withIsolatedDefaults { defaults in
            let preferences = AppPreferences(defaults: defaults)
            preferences.coreScope = .busiest
            preferences.visualization = .numbers

            let restored = AppPreferences(defaults: defaults)

            XCTAssertEqual(restored.coreScope, .busiest)
            XCTAssertEqual(restored.visualization, .numbers)
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
