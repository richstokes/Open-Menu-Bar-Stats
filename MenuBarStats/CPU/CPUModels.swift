import Foundation

enum SystemThermalState: String, Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal:
            self = .nominal
        case .fair:
            self = .fair
        case .serious:
            self = .serious
        case .critical:
            self = .critical
        @unknown default:
            self = .nominal
        }
    }

    var title: String {
        switch self {
        case .nominal: "OK"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        }
    }

    /// Normal operation stays icon-only; exceptional states earn menu-bar text.
    var menuBarTitle: String? {
        self == .nominal ? nil : title
    }

    static var current: Self {
        Self(ProcessInfo.processInfo.thermalState)
    }
}

struct CPUTicks: Equatable, Sendable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32
}

struct CPUCoreReading: Identifiable, Equatable, Sendable {
    let id: Int
    let usage: Double

    var clampedUsage: Double {
        min(max(usage, 0), 1)
    }

    var percentage: Int {
        Int((clampedUsage * 100).rounded())
    }

    var label: String {
        "Core \(id + 1)"
    }
}

struct CPUSnapshot: Equatable, Sendable {
    let cores: [CPUCoreReading]
    let overallUsage: Double
    let timestamp: Date

    var clampedOverallUsage: Double {
        min(max(overallUsage, 0), 1)
    }

    var overallPercentage: Int {
        Int((clampedOverallUsage * 100).rounded())
    }

    var busiestCore: CPUCoreReading? {
        cores.reduce(nil) { current, candidate in
            guard let current else { return candidate }
            return candidate.usage > current.usage ? candidate : current
        }
    }
}
