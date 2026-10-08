import SwiftUI

/// The menu shown from Glasspad's menu bar icon.
struct MenuBarMenu: View {
    @Environment(EntryStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Menu("Open Recent") {
            ForEach(recentEntries) { entry in
                Button(Self.truncated(entry.title)) {
                    store.select(entry.id)
                    showWindow()
                }
            }
        }
        .disabled(recentEntries.isEmpty)
        Button("New Entry") {
            store.createEntry()
            showWindow()
        }
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Glasspad") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var recentEntries: [Entry] {
        Array(store.entries
            .filter { !$0.isBlank }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(10))
    }

    /// Reopens the window if the user closed it, and brings it to the front.
    private func showWindow() {
        NSApp.activate()
        openWindow(id: "main")
    }

    private static func truncated(_ title: String) -> String {
        title.count > 40 ? title.prefix(40) + "…" : title
    }
}
