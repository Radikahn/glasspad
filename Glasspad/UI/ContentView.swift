import SwiftUI

struct ContentView: View {
    @Environment(EntryStore.self) private var store
    @Environment(GlassSettings.self) private var glass
    @State private var status = EditorStatus()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 38)
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                EditorView(
                    entryID: store.selectedID,
                    text: store.selectedEntry?.body ?? "",
                    showsScrollBar: glass.showsScrollBar,
                    status: status,
                    onChange: { id, text in store.updateBody(id, text) })
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.025),
                                .init(color: .black, location: 0.97),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom)
                    }
                StatusBar(status: status)
            }

            if store.showSidebar {
                SidebarView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            IconButton(systemName: "sidebar.right", help: "Entries (⌃⌘S)", active: store.showSidebar) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                    store.toggleSidebar()
                }
            }
            .padding(.top, 5)
            .padding(.trailing, 12)
        }
        .background { GlassBackground() }
        .background { WindowConfigurator() }
        .ignoresSafeArea()
        .frame(minWidth: 340, idealWidth: 460, minHeight: 420, idealHeight: 640)
        .preferredColorScheme(.dark)
    }
}
