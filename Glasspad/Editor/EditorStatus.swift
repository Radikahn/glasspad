import Observation

enum VimMode {
    case normal, insert, visual, visualLine, search

    var isVisual: Bool { self == .visual || self == .visualLine }
}

/// What the status line shows; written by the text view.
@Observable
final class EditorStatus {
    var mode: VimMode = .normal
    var searchQuery = ""
    var matchIndex = 0
    var matchCount = 0
    var wordCount = 0
}
