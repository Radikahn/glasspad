import SwiftUI

struct SidebarView: View {
    @Environment(EntryStore.self) private var store
    @Environment(GlassSettings.self) private var glass

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Entries")
                    .font(.mono(11, bold: true))
                    .foregroundStyle(.white.opacity(0.55))
                Text("\(store.entries.count)")
                    .font(.mono(10))
                    .foregroundStyle(.white.opacity(0.28))
                Spacer()
                IconButton(systemName: "plus", help: "New entry (⌘N)") {
                    store.createEntry()
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 46)
            .frame(height: 32)
            .padding(.bottom, 6)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.entries) { entry in
                        EntryRow(entry: entry, selected: entry.id == store.selectedID)
                            .onTapGesture { store.select(entry.id) }
                            .contextMenu {
                                Button("Delete Entry", role: .destructive) {
                                    store.delete(entry.id)
                                }
                            }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 228)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                VisualEffect(material: .hudWindow, blending: .withinWindow)
                glass.tint(dimmed: 0.33).opacity(0.55)
            }
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(.white.opacity(0.07)).frame(width: 1)
        }
    }
}

private struct EntryRow: View {
    let entry: Entry
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.title)
                .font(.mono(12, bold: true))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            if !entry.preview.isEmpty {
                Text(entry.preview)
                    .font(.mono(10.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
            }
            Text(entry.createdAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                .font(.mono(9.5))
                .foregroundStyle(.white.opacity(0.28))
                .padding(.top, 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.glassAccent.opacity(0.16) : .white.opacity(hovering ? 0.05 : 0))
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.glassAccent.opacity(0.18), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

struct IconButton: View {
    let systemName: String
    var help: String = ""
    var active = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(hovering || active ? 0.85 : 0.42))
                .frame(width: 26, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.white.opacity(hovering ? 0.09 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .help(help)
    }
}
