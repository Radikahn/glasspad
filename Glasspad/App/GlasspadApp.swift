import SwiftUI

@main
struct GlasspadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: EntryStore
    @State private var glass = GlassSettings()

    init() {
        Theme.registerFonts()
        _store = State(initialValue: EntryStore())
    }

    var body: some Scene {
        Window("Glasspad", id: "main") {
            ContentView()
                .environment(store)
                .environment(glass)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 460, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Entry") { store.createEntry() }
                    .keyboardShortcut("n")
                Button("Delete Entry") {
                    if let id = store.selectedID { store.delete(id) }
                }
            }
            CommandGroup(replacing: .sidebar) {
                Button(store.showSidebar ? "Hide Entries" : "Show Entries") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                        store.toggleSidebar()
                    }
                }
                .keyboardShortcut("s", modifiers: [.control, .command])
            }
        }

        MenuBarExtra {
            MenuBarMenu()
                .environment(store)
        } label: {
            Image("MenuBarIcon")
        }

        Settings {
            SettingsView()
                .environment(glass)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        // `pkill` / `just run` send SIGTERM; quit normally so pending edits get saved.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSignal = source
        // macOS draws bundle icons on a squircle background; a runtime icon keeps the PNG's transparency.
        if let icon = NSImage(named: "DockIcon") {
            NSApp.applicationIconImage = icon
        }
    }

    /// Closing the window keeps Glasspad running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
