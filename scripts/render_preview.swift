import AppKit
import SwiftUI

@main
struct PreviewRenderer {
    @MainActor
    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 3 else {
            fputs("Usage: render-preview <overview|processes|performance> <output-path>\n", stderr)
            Foundation.exit(1)
        }

        guard let section = AppSection(rawValue: args[1].capitalized) else {
            fputs("Unknown section: \(args[1])\n", stderr)
            Foundation.exit(1)
        }

        let outputURL = URL(fileURLWithPath: args[2])

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let store = MonitorStore()
        store.appearance = .light
        store.selectedSection = section
        store.selectedMetric = .cpu
        store.sortKey = .cpu
        store.sortAscending = false
        store.startSampling()

        try? await Task.sleep(for: .seconds(2))

        let content = ContentView()
            .environmentObject(store)

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 960, height: 640)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            fputs("Failed to create bitmap representation.\n", stderr)
            store.stopSampling()
            Foundation.exit(1)
        }

        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fputs("Failed to encode PNG.\n", stderr)
            store.stopSampling()
            Foundation.exit(1)
        }

        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try png.write(to: outputURL)
            print(outputURL.path)
            store.stopSampling()
            Foundation.exit(0)
        } catch {
            fputs("Failed to write preview frame: \(error)\n", stderr)
            store.stopSampling()
            Foundation.exit(1)
        }
    }
}
