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
    func testAppStoreScreenshotsRender() throws {
        let snapshot = CPUSnapshot(
            cores: [0.12, 0.28, 0.46, 0.81, 0.37, 0.64, 0.21, 0.93, 0.55, 0.34]
                .enumerated()
                .map { CPUCoreReading(id: $0.offset, usage: $0.element) },
            overallUsage: 0.47,
            timestamp: Date(timeIntervalSince1970: 0)
        )
        let memorySnapshot = MemorySnapshot(
            usedBytes: 8 * 1_024 * 1_024 * 1_024,
            totalBytes: 16 * 1_024 * 1_024 * 1_024,
            timestamp: Date(timeIntervalSince1970: 0)
        )
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenMenuStatsAppStoreScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let configurations: [(
            filename: String,
            title: String,
            subtitle: String,
            scope: CoreScope,
            visualization: CPUVisualization,
            scale: CGFloat
        )] = [
            (
                "01-every-core.png",
                "Every core.\nOne glance.",
                "See all cores in compact bars and change the view in a click.",
                .all,
                .bars,
                0.78
            ),
            (
                "02-busiest-core.png",
                "Focus on the\nbusiest core.",
                "Switch to a clean numeric reading whenever precision matters.",
                .busiest,
                .numbers,
                0.84
            ),
        ]

        for configuration in configurations {
            let suiteName = "MenuBarStatsAppStoreScreenshots.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }

            let preferences = AppPreferences(defaults: defaults)
            preferences.coreScope = configuration.scope
            preferences.visualization = configuration.visualization
            preferences.showsMemory = true
            preferences.showsThermalState = true
            let monitor = CPUMonitor(
                snapshot: snapshot,
                memorySnapshot: memorySnapshot,
                thermalState: .nominal
            )
            let appView = CPUMenuView(monitor: monitor, preferences: preferences)
                .environment(\.colorScheme, .light)
                .background(Color(nsColor: .windowBackgroundColor))

            let screenshot = AppStoreScreenshot(
                title: configuration.title,
                subtitle: configuration.subtitle,
                contentScale: configuration.scale,
                content: AnyView(appView)
            )
            try writeAppStoreScreenshot(
                screenshot,
                to: outputDirectory.appendingPathComponent(configuration.filename)
            )
        }

        let aboutScreenshot = AppStoreScreenshot(
            title: "Open source,\nprivacy first.",
            subtitle: "No accounts. No analytics. No network access.",
            contentScale: 1,
            content: AnyView(
                AboutView()
                    .environment(\.colorScheme, .light)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
        )
        try writeAppStoreScreenshot(
            aboutScreenshot,
            to: outputDirectory.appendingPathComponent("03-open-source.png")
        )
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

    @MainActor
    private func writeAppStoreScreenshot<Content: View>(
        _ view: Content,
        to outputURL: URL
    ) throws {
        let logicalSize = CGSize(width: 720, height: 450)
        let scale: CGFloat = 4
        let hostingView = NSHostingView(
            rootView: view.frame(width: logicalSize.width, height: logicalSize.height)
        )
        hostingView.appearance = NSAppearance(named: .aqua)
        hostingView.frame = NSRect(origin: .zero, size: logicalSize)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        let pixelWidth = Int(logicalSize.width * scale)
        let pixelHeight = Int(logicalSize.height * scale)
        let renderedBitmap = try XCTUnwrap(
            unsafe NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelWidth,
                pixelsHigh: pixelHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        renderedBitmap.size = logicalSize
        hostingView.cacheDisplay(in: hostingView.bounds, to: renderedBitmap)
        window.close()

        let renderedImage = try XCTUnwrap(renderedBitmap.cgImage)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(
            unsafe CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 40 / 255, green: 94 / 255, blue: 127 / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.draw(renderedImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        let flattenedImage = try XCTUnwrap(context.makeImage())
        let bitmap = NSBitmapImageRep(cgImage: flattenedImage)
        let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try pngData.write(to: outputURL, options: .atomic)

        XCTAssertEqual(bitmap.pixelsWide, 2_880)
        XCTAssertEqual(bitmap.pixelsHigh, 1_800)
        XCTAssertGreaterThan(pngData.count, 100_000)
    }
}

private struct AppStoreScreenshot: View {
    let title: String
    let subtitle: String
    let contentScale: CGFloat
    let content: AnyView

    var body: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 76, height: 76)

                Text("OPEN MENU BAR STATS")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(paletteYellow)

                Text(title)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Label("Built for macOS Tahoe", systemImage: "apple.logo")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
            .frame(width: 260, alignment: .leading)

            content
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 18, y: 12)
                .scaleEffect(contentScale)
                .frame(width: 336, height: 390)
        }
        .padding(.horizontal, 46)
        .padding(.vertical, 30)
        .background {
            ZStack(alignment: .trailing) {
                paletteDeepBlue
                Rectangle()
                    .fill(paletteBlue.opacity(0.26))
                    .frame(width: 255)
            }
        }
    }

    private var paletteBlue: Color {
        Color(red: 68 / 255, green: 127 / 255, blue: 166 / 255)
    }

    private var paletteYellow: Color {
        Color(red: 237 / 255, green: 205 / 255, blue: 99 / 255)
    }

    private var paletteDeepBlue: Color {
        Color(red: 40 / 255, green: 94 / 255, blue: 127 / 255)
    }
}
