import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Files double-clicked in Finder (or dropped on the Dock icon) before the window exists.
    static var pendingOpens: [URL] = []
    static var openHandler: (([URL]) -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        if let handler = AppDelegate.openHandler {
            handler(urls)
        } else {
            AppDelegate.pendingOpens += urls
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct Sims3ManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = Store()

    var body: some Scene {
        Window("Sims 3 Manager", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 760, minHeight: 600)
                .onAppear {
                    AppDelegate.openHandler = { urls in
                        store.importItems(urls)
                        store.showImport()
                    }
                    if !AppDelegate.pendingOpens.isEmpty {
                        store.importItems(AppDelegate.pendingOpens)
                        store.showImport()
                        AppDelegate.pendingOpens = []
                    }
                    store.updateVisibility()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import…") { store.chooseFilesToImport() }
                    .keyboardShortcut("o")
            }
        }
    }
}
