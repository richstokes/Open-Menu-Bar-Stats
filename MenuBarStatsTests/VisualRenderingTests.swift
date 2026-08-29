import AppKit
import SwiftUI
import XCTest
@testable import MenuBarStats

final class VisualRenderingTests: XCTestCase {
    @MainActor
    func testReferenceLayoutsRender() throws {
        let snapshot = CPUSnapshot(
            cores: [0.12, 0.28, 0.46, 0.81, 0.37, 0.64, 0.21, 0.93, 0.55, 0.34]
                .enumerated()
                .map { CPUCoreReading(id: $0.offset, usage: $0.element) },
            overallUsage: 0.47,
            timestamp: Date(timeIntervalSince1970: 0)
        )
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuBarStatsPreviews", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        for scope in CoreScope.allCases {
            for visualization in CPUVisualization.allCases {
                let suiteName = "MenuBarStatsVisualTests.\(UUID().uuidString)"
                let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
                defer { defaults.removePersistentDomain(forName: suiteName) }

                let preferences = AppPreferences(defaults: defaults)
                preferences.coreScope = scope
                preferences.visualization = visualization
                preferences.showsThermalState = true
                let monitor = CPUMonitor(snapshot: snapshot)
                let view = CPUMenuView(monitor: monitor, preferences: preferences)
                    .environment(\.colorScheme, .light)
                    .background(Color(nsColor: .windowBackgroundColor))

                let bitmap = try render(view)
                let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                let outputURL = outputDirectory
                    .appendingPathComponent("\(scope.rawValue)-\(visualization.rawValue).png")
                try pngData.write(to: outputURL, options: .atomic)

                XCTAssertGreaterThan(bitmap.size.width, 300)
                XCTAssertGreaterThan(bitmap.size.height, 300)
                XCTAssertGreaterThan(pngData.count, 10_000)
            }
        }
    }

    @MainActor
    func testMetricStatusLabelsRenderIndependently() throws {
        let suiteName = "MenuBarStatsStatusVisualTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppPreferences(defaults: defaults)
        preferences.visualization = .numbers
        preferences.showsMemory = true
        preferences.showsThermalState = false

        let monitor = CPUMonitor(
            snapshot: CPUSnapshot(
                cores: [CPUCoreReading(id: 0, usage: 0.47)],
                overallUsage: 0.47,
                timestamp: Date(timeIntervalSince1970: 0)
            ),
            memorySnapshot: MemorySnapshot(
                usedBytes: 8 * 1_024 * 1_024 * 1_024,
                totalBytes: 16 * 1_024 * 1_024 * 1_024,
                timestamp: Date(timeIntervalSince1970: 0)
            ),
            thermalState: .fair
        )
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuBarStatsPreviews", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let labels: [(name: String, view: AnyView)] = [
            ("status-cpu", AnyView(CPUStatusLabel(monitor: monitor, preferences: preferences))),
            ("status-memory", AnyView(MemoryStatusLabel(monitor: monitor))),
            ("status-thermal", AnyView(ThermalStatusLabel(monitor: monitor))),
        ]

        for label in labels {
            let view = label.view
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .environment(\.colorScheme, .light)
                .background(Color(nsColor: .windowBackgroundColor))
            let bitmap = try renderFitting(view)
            let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try pngData.write(
                to: outputDirectory.appendingPathComponent("\(label.name).png"),
                options: .atomic
            )

            XCTAssertGreaterThan(bitmap.size.width, 40)
            XCTAssertLessThan(bitmap.size.width, 120)
            XCTAssertGreaterThan(bitmap.size.height, 20)
            XCTAssertGreaterThan(pngData.count, 500)
        }
    }

    @MainActor
    func testAboutViewRenders() throws {
        let view = AboutView()
            .environment(\.colorScheme, .light)
            .background(Color(nsColor: .windowBackgroundColor))
        let bitmap = try renderFitting(view)
        let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))

        XCTAssertGreaterThanOrEqual(bitmap.size.width, 300)
        XCTAssertGreaterThan(bitmap.size.height, 180)
        XCTAssertGreaterThan(pngData.count, 5_000)
    }

    @MainActor
    private func render<Content: View>(_ view: Content) throws -> NSBitmapImageRep {
        let hostingView = NSHostingView(rootView: view)
        hostingView.appearance = NSAppearance(named: .aqua)
        hostingView.frame = NSRect(x: 0, y: 0, width: 340, height: 600)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        let fittingSize = hostingView.fittingSize
        hostingView.frame.size = NSSize(width: 340, height: fittingSize.height)
        window.setContentSize(hostingView.frame.size)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        window.close()
        return bitmap
    }

    @MainActor
    private func renderFitting<Content: View>(_ view: Content) throws -> NSBitmapImageRep {
        let hostingView = NSHostingView(rootView: view)
        hostingView.appearance = NSAppearance(named: .aqua)
        hostingView.frame = NSRect(x: 0, y: 0, width: 300, height: 50)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        hostingView.frame.size = hostingView.fittingSize
        window.setContentSize(hostingView.frame.size)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        window.close()
        return bitmap
    }
}
