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
}
