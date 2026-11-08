import AppKit
import SwiftUI

/// Saves pictures of the main screens for the README by drawing the real app interface
/// into a window that is never shown. This works with the screen locked or asleep and
/// needs no Screen Recording permission.
///   Sims3Manager --screenshots /some/folder
@MainActor
enum Screenshotter {
    static func run(to dir: URL) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let store = Store()
        store.screenshotMode = true
        // Show the defaults a new user sees.
        store.displayAutomatic = true
        store.soundAutomatic = true
        store.notice = nil
        let size = NSSize(width: 1100, height: 780)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Sims 3 Manager"
        window.contentView = NSHostingView(rootView: ContentView().environmentObject(store)
            .frame(width: size.width, height: size.height))

        let shots: [(String, Pane, Bool)] = [
            ("home", .play, false),
            ("home-import", .play, true),
            ("mods", .mods, false),
            ("stream-deck", .streamDeck, false),
            ("tools", .tools, false),
        ]
        wait(3)   // let the mod list finish reading names and types
        for (name, pane, importOpen) in shots {
            store.pane = pane
            store.importExpanded = importOpen
            store.notice = nil
            wait(1.5)
            save(window, to: dir.appendingPathComponent("\(name).png"))
        }
    }

    private static func wait(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func save(_ window: NSWindow, to url: URL) {
        // The frame view includes the title bar and toolbar as well as the content.
        guard let view = window.contentView?.superview ?? window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        view.display()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("saved \(url.lastPathComponent) \(rep.pixelsWide)x\(rep.pixelsHigh)")
    }
}
