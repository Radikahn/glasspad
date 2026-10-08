import AppKit
import Observation

@Observable
final class EntryStore {
    private(set) var entries: [Entry] = []
    private(set) var selectedID: Int64?
    var showSidebar = false

    @ObservationIgnored private let db: Database?
    @ObservationIgnored private var dirty: Set<Int64> = []
    @ObservationIgnored private var saveTimer: Timer?
    @ObservationIgnored private var fallbackID: Int64 = -1

    init() {
        do {
            db = try Database(url: Database.defaultURL())
        } catch {
            NSLog("Glasspad: database unavailable, entries will not persist: \(error)")
            db = nil
        }
        entries = db?.fetchEntries() ?? []
        if entries.isEmpty {
            _ = insertEntry(body: Self.welcomeText)
        }
        selectedID = entries.first?.id

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.flush()
        }
    }

    var selectedEntry: Entry? {
        entries.first { $0.id == selectedID }
    }

    // MARK: Mutations

    func createEntry() {
        if let current = selectedEntry, current.isBlank { return }
        flush()
        let previous = selectedID
        selectedID = insertEntry(body: "")
        discardIfBlank(previous)
    }

    func select(_ id: Int64) {
        guard id != selectedID else { return }
        flush()
        let previous = selectedID
        selectedID = id
        discardIfBlank(previous)
    }

    func updateBody(_ id: Int64, _ body: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].body != body else { return }
        entries[index].body = body
        entries[index].updatedAt = Date()
        dirty.insert(id)
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            self?.flush()
        }
    }

    func delete(_ id: Int64) {
        dirty.remove(id)
        db?.deleteEntry(id: id)
        entries.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = entries.first?.id ?? insertEntry(body: "")
        }
    }

    func toggleSidebar() {
        showSidebar.toggle()
    }

    func flush() {
        saveTimer?.invalidate()
        saveTimer = nil
        for id in dirty {
            guard let entry = entries.first(where: { $0.id == id }) else { continue }
            db?.updateEntry(id: id, body: entry.body, updatedAt: entry.updatedAt)
        }
        dirty.removeAll()
    }

    // MARK: Private

    private func insertEntry(body: String) -> Int64 {
        let now = Date()
        let id: Int64
        if let newID = db?.insertEntry(body: body, date: now) {
            id = newID
        } else {
            id = fallbackID
            fallbackID -= 1
        }
        entries.insert(Entry(id: id, body: body, createdAt: now, updatedAt: now), at: 0)
        return id
    }

    /// Leaving an empty page behind just clutters the sidebar.
    private func discardIfBlank(_ id: Int64?) {
        guard let id, id != selectedID,
              let entry = entries.first(where: { $0.id == id }), entry.isBlank else { return }
        delete(id)
    }

    private static let welcomeText = """
        # Welcome to Glasspad

        A quiet place to write. Everything is **markdown**, rendered *live* as you type.

        ## Vim keys
        - `i` `a` `o` enter insert mode, `esc` returns to normal
        - `h` `j` `k` `l` move the cursor, `w` `b` jump by word
        - `/` searches, `n` and `N` cycle through matches
        - `x` deletes a character, `dd` a line, `u` undoes

        ## Code
        Click the language label on a block to change its highlighting.

        ```swift
        struct Thought {
            let text: String
            var isKept = true  // keep the good ones
        }
        ```

        > Write what you see, not what you think you should see.

        - [ ] write something today
        - [x] open Glasspad
        """
}
