import Foundation
import Observation

enum CoreScope: String, CaseIterable, Identifiable, Sendable {
    case all = "all"
    case busiest = "busiest"

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All cores"
        case .busiest: "Busiest"
        }
    }
}

enum CPUVisualization: String, CaseIterable, Identifiable, Sendable {
    case bars = "bars"
    case numbers = "numbers"

    var id: Self { self }

    var title: String {
        switch self {
        case .bars: "Bars"
        case .numbers: "Numbers"
        }
    }
}

@Observable
final class AppPreferences {
    enum Keys {
        static let coreScope = "cpu.scope"
        static let visualization = "cpu.visualization"
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    var coreScope: CoreScope {
        didSet { defaults.set(coreScope.rawValue, forKey: Keys.coreScope) }
    }

    var visualization: CPUVisualization {
        didSet { defaults.set(visualization.rawValue, forKey: Keys.visualization) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        coreScope = CoreScope(rawValue: defaults.string(forKey: Keys.coreScope) ?? "") ?? .all
        visualization = CPUVisualization(
            rawValue: defaults.string(forKey: Keys.visualization) ?? ""
        ) ?? .bars
    }
}
