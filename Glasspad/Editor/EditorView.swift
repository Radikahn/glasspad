import SwiftUI

struct EditorView: NSViewRepresentable {
    let entryID: Int64?
    let text: String
    let showsScrollBar: Bool
    let status: EditorStatus
    let onChange: (Int64, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let (scroll, textView) = VimTextView.makeScrollable()
        textView.delegate = context.coordinator
        textView.status = status
        context.coordinator.textView = textView
        context.coordinator.onChange = onChange
        context.coordinator.load(id: entryID, text: text)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if scroll.hasVerticalScroller != showsScrollBar {
            scroll.hasVerticalScroller = showsScrollBar
        }
        context.coordinator.onChange = onChange
        if context.coordinator.loadedID != entryID {
            context.coordinator.load(id: entryID, text: text)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: VimTextView?
        var loadedID: Int64?
        var onChange: ((Int64, String) -> Void)?
        private let undo = UndoManager()

        func load(id: Int64?, text: String) {
            loadedID = id
            guard let textView else { return }
            undo.removeAllActions()
            textView.onTextChange = { [weak self] newText in
                guard let self, let id = self.loadedID else { return }
                self.onChange?(id, newText)
            }
            let isBlank = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            textView.load(text: text, insertMode: isBlank)
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        /// Each entry gets its own undo history.
        func undoManager(for view: NSTextView) -> UndoManager? {
            undo
        }
    }
}
