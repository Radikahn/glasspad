import AppKit
import QuartzCore

/// The editor: an NSTextView (TextKit 1) with live markdown styling, a
/// smearing cursor, and a small vim layer (see VimTextView+Vim.swift).
final class VimTextView: NSTextView {
    weak var status: EditorStatus?
    var onTextChange: ((String) -> Void)?

    var mode: VimMode = .normal {
        didSet {
            guard mode != oldValue else { return }
            publishStatus()
            updateCursor(animated: true)
        }
    }

    // Rendering
    private var storageRef: NSTextStorage?
    private(set) var codeBlocks: [CodeBlock] = []
    private var activeParagraph = NSRange(location: NSNotFound, length: 0)
    private var editInProgress = false
    private var isRestyling = false
    private var pills: [LanguagePill] = []

    // Cursor
    private var smear = SmearCursor()
    private var displayLinkRef: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var cursorTextRange: NSRange?

    // Vim state (used by the extension)
    var pendingOperator = ""
    var pendingCount = 1
    var countBuffer = ""
    var goalX: CGFloat?
    var preserveGoal = false

    // Visual mode: the selection runs from the anchor to the head (the cursor), inclusive.
    var visualAnchor = 0
    var visualHead = 0

    /// The unnamed register. Yanks also go to the system clipboard; `changeCount`
    /// tells whether the clipboard still holds our yank (and so whether it was linewise).
    struct YankRegister {
        var text: String
        var linewise: Bool
        var changeCount: Int
    }
    var register: YankRegister?
    var pasteboard: NSPasteboard = .general

    // Search state
    var searchQuery = ""
    var searchOrigin = 0
    var lastSearch = ""
    var searchMatches: [NSRange] = []
    var currentMatch: Int?

    // MARK: Setup

    static func makeScrollable() -> (NSScrollView, VimTextView) {
        let storage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = VimTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 300), textContainer: container)
        textView.storageRef = storage
        textView.configure()

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = textView
        return (scroll, textView)
    }

    private func configure() {
        drawsBackground = false
        backgroundColor = .clear
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        smartInsertDeleteEnabled = false
        usesFindBar = false
        writingToolsBehavior = .none
        inlinePredictionType = .no
        insertionPointColor = .clear
        selectedTextAttributes = [.backgroundColor: Theme.selection]
        textContainerInset = Theme.textInset
        typingAttributes = Theme.baseAttributes
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    func load(text: String, insertMode: Bool) {
        searchMatches = []
        lastSearch = ""
        currentMatch = nil
        pendingOperator = ""
        countBuffer = ""
        goalX = nil
        smear = SmearCursor()
        isRestyling = true
        string = text
        setSelectedRange(NSRange(location: 0, length: 0))
        isRestyling = false
        mode = insertMode ? .insert : .normal
        restyle()
        updateCursor(animated: false)
        scroll(.zero)
        publishStatus()
        publishWordCount()
    }

    // MARK: Lifecycle

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let clip = superview as? NSClipView else { return }
        clip.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipFrameChanged), name: NSView.frameDidChangeNotification, object: clip)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(focusChanged), name: name, object: window)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
            self.updateCursor(animated: false)
        }
    }

    @objc private func clipFrameChanged() {
        guard let clip = superview else { return }
        minSize = NSSize(width: 0, height: clip.bounds.height)
        if frame.height < clip.bounds.height {
            setFrameSize(NSSize(width: frame.width, height: clip.bounds.height))
        }
    }

    @objc private func focusChanged() {
        updateCursor(animated: false)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        updateCursor(animated: false)
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        updateCursor(animated: false)
        return resigned
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged {
            updatePills()
            updateCursor(animated: false)
        }
    }

    // MARK: Editing hooks

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let ok = super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        if ok { editInProgress = true }
        return ok
    }

    override func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        let ok = super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings)
        if ok { editInProgress = true }
        return ok
    }

    override func didChangeText() {
        super.didChangeText()
        editInProgress = false
        guard !hasMarkedText() else { return }
        // An edit from outside the vim layer (e.g. ⌘V over a visual selection) ends visual mode.
        if mode.isVisual { mode = .normal }
        restyle()
        refreshSearchMatches()
        updateCursor(animated: true)
        publishWordCount()
        onTextChange?(string)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        var ranges = ranges
        var newMode: VimMode?
        // Selecting with the mouse enters visual mode; a plain click leaves it.
        if !stillSelecting, !editInProgress, !isRestyling, ranges.count == 1,
           mode == .normal || mode.isVisual, Self.isMouseEvent(NSApp.currentEvent) {
            let range = ranges[0].rangeValue
            if range.length > 0 {
                visualAnchor = range.location
                visualHead = prevIndex(NSMaxRange(range))
                if mode != .visual { newMode = .visual }
            } else if mode.isVisual {
                newMode = .normal
            }
        }
        // Normal mode never rests on a line's newline (unless the line is empty).
        if (newMode ?? mode) == .normal, !stillSelecting, ranges.count == 1, ranges[0].rangeValue.length == 0 {
            let clamped = clampNormal(ranges[0].rangeValue.location)
            ranges = [NSValue(range: NSRange(location: clamped, length: 0))]
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if let newMode { mode = newMode }
        guard !editInProgress, !isRestyling, textStorage != nil else { return }
        if !preserveGoal { goalX = nil }
        if !stillSelecting, paragraphForSelection() != activeParagraph {
            restyle()
        }
        updateCursor(animated: true)
    }

    private static func isMouseEvent(_ event: NSEvent?) -> Bool {
        guard let type = event?.type else { return false }
        return type == .leftMouseDown || type == .leftMouseUp || type == .leftMouseDragged
    }

    /// ⌘A selects everything as a visual selection, so `d` / `y` act on it.
    override func selectAll(_ sender: Any?) {
        guard mode == .normal || mode.isVisual, textLength > 0 else {
            super.selectAll(sender)
            return
        }
        visualAnchor = 0
        visualHead = clampNormal(textLength)
        mode = .visual
        applyVisualSelection()
    }

    // MARK: Styling

    private func paragraphForSelection() -> NSRange {
        let text = string as NSString
        let selection = selectedRange()
        guard selection.location <= text.length else { return NSRange(location: NSNotFound, length: 0) }
        return text.paragraphRange(for: selection)
    }

    func restyle() {
        guard let storage = textStorage else { return }
        isRestyling = true
        activeParagraph = paragraphForSelection()
        codeBlocks = MarkdownStyler.style(storage, active: activeParagraph)
        typingAttributes = Theme.baseAttributes
        isRestyling = false
        updatePills()
        needsDisplay = true
    }

    private func updatePills() {
        guard let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        while pills.count < codeBlocks.count {
            let pill = LanguagePill()
            addSubview(pill)
            pills.append(pill)
        }
        while pills.count > codeBlocks.count {
            pills.removeLast().removeFromSuperview()
        }
        let origin = textContainerOrigin
        for (pill, block) in zip(pills, codeBlocks) {
            pill.language = block.language
            let blockStart = block.range.location
            pill.onSelect = { [weak self] language in
                self?.setLanguage(language, forBlockAt: blockStart)
            }
            guard let top = fragmentsRect(NSRange(location: block.range.location, length: 1)) else {
                pill.isHidden = true
                continue
            }
            pill.isHidden = false
            let width = pill.fittingWidth
            let x = origin.x + textContainer.size.width + Theme.codeBlockOutset - width - 6
            let y = origin.y + top.minY + max(2, (top.height - LanguagePill.height) / 2)
            pill.frame = NSRect(x: x, y: y, width: width, height: LanguagePill.height)
        }
    }

    func setLanguage(_ language: String, forBlockAt location: Int) {
        guard let block = codeBlocks.first(where: { $0.range.location == location }) else { return }
        breakUndoCoalescing()
        replaceText(in: block.languageRange, with: language)
        breakUndoCoalescing()
    }

    /// An undoable programmatic edit.
    func replaceText(in range: NSRange, with replacement: String) {
        guard let storage = textStorage, shouldChangeText(in: range, replacementString: replacement) else { return }
        storage.replaceCharacters(in: range, with: replacement)
        didChangeText()
    }

    // MARK: Status

    func publishStatus() {
        guard let status else { return }
        if status.mode != mode { status.mode = mode }
        let query = mode == .search ? searchQuery : lastSearch
        if status.searchQuery != query { status.searchQuery = query }
        if status.matchCount != searchMatches.count { status.matchCount = searchMatches.count }
        let index = (currentMatch ?? -1) + 1
        if status.matchIndex != index { status.matchIndex = index }
    }

    private func publishWordCount() {
        let count = string.split(whereSeparator: { $0.isWhitespace }).count
        if status?.wordCount != count { status?.wordCount = count }
    }

    // MARK: Geometry

    /// Union of the line fragments covering a character range, in container coordinates.
    private func fragmentsRect(_ characterRange: NSRange) -> NSRect? {
        guard let layoutManager else { return nil }
        let glyphs = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        var result: NSRect?
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
            result = result?.union(rect) ?? rect
        }
        return result
    }

    /// Rects tightly hugging the text of a character range (one per line), in view coordinates.
    private func textRects(_ characterRange: NSRange, padding: CGFloat) -> [NSRect] {
        guard let layoutManager, let textContainer, let storage = textStorage,
              NSMaxRange(characterRange) <= storage.length else { return [] }
        let glyphs = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        var enclosing: [NSRect] = []
        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: textContainer
        ) { rect, _ in enclosing.append(rect) }

        let font = storage.attribute(.font, at: characterRange.location, effectiveRange: nil) as? NSFont ?? Theme.font()
        let origin = textContainerOrigin
        return enclosing.compactMap { rect in
            guard rect.width > 0 else { return nil }
            let glyph = layoutManager.glyphIndex(for: NSPoint(x: rect.minX + 0.5, y: rect.midY), in: textContainer)
            let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let baseline = line.minY + layoutManager.location(forGlyphAt: glyph).y
            let top = baseline - font.ascender - padding / 2
            let bottom = baseline - font.descender + padding / 2
            return NSRect(x: origin.x + rect.minX - padding, y: origin.y + top,
                          width: rect.width + padding * 2, height: bottom - top)
        }
    }

    private func spaceWidth(_ font: NSFont) -> CGFloat {
        (" " as NSString).size(withAttributes: [.font: font]).width
    }

    /// Where the cursor sits for a character index, in view coordinates.
    func caretRect(for index: Int, block: Bool) -> NSRect {
        guard let layoutManager, let textContainer, let storage = textStorage else { return .zero }
        layoutManager.ensureLayout(for: textContainer)
        let origin = textContainerOrigin
        let text = storage.string as NSString
        let length = text.length
        let barWidth: CGFloat = 2

        if index >= length, length == 0 || text.character(at: length - 1) == 10 {
            let font = typingAttributes[.font] as? NSFont ?? Theme.font()
            let fragment = layoutManager.extraLineFragmentRect
            let x = layoutManager.extraLineFragmentUsedRect.origin.x
            return NSRect(x: origin.x + x, y: origin.y + fragment.minY,
                          width: block ? Theme.charWidth : barWidth, height: font.ascender - font.descender)
        }

        let charIndex = min(index, length - 1)
        let pastEnd = index >= length
        let glyph = layoutManager.glyphIndexForCharacter(at: charIndex)
        var lineGlyphs = NSRange()
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineGlyphs)
        let location = layoutManager.location(forGlyphAt: glyph)
        let font = storage.attribute(.font, at: charIndex, effectiveRange: nil) as? NSFont ?? Theme.font()

        var width: CGFloat
        let character = text.character(at: charIndex)
        if character == 10 || character == 13 {
            width = spaceWidth(font)
        } else if NSLocationInRange(glyph + 1, lineGlyphs) {
            width = layoutManager.location(forGlyphAt: glyph + 1).x - location.x
        } else {
            width = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer).width
        }
        if width < 1 { width = spaceWidth(font) }

        var x = line.minX + location.x
        if pastEnd {
            x += width
            width = spaceWidth(font)
        }
        let baseline = line.minY + location.y
        return NSRect(x: origin.x + x, y: origin.y + baseline - font.ascender,
                      width: block ? width : barWidth, height: font.ascender - font.descender)
    }

    // MARK: Cursor

    private var hasFocus: Bool {
        window?.isKeyWindow == true && window?.firstResponder === self
    }

    func updateCursor(animated: Bool) {
        guard let storage = textStorage else { return }
        let before = smear.bounds
        clearCursorText()

        let selection = selectedRange()
        smear.isHidden = selection.length > 0 && !mode.isVisual
        if !smear.isHidden {
            let index = mode.isVisual ? visualHead : selection.location
            let rect = caretRect(for: min(index, storage.length), block: mode != .insert)
            smear.move(to: rect, animated: animated && window != nil)
            if smear.isAnimating { startDisplayLink() } else { applyCursorText() }
        }
        invalidate(before.union(smear.bounds))
    }

    private func invalidate(_ rect: NSRect) {
        guard !rect.isNull else { return }
        setNeedsDisplay(rect.insetBy(dx: -4, dy: -4))
    }

    /// Draw the character under a resting block cursor in a dark color so it reads through the block.
    private func applyCursorText() {
        guard mode != .insert, hasFocus, !smear.isHidden, !smear.isAnimating,
              let layoutManager, let storage = textStorage else { return }
        let index = mode.isVisual ? visualHead : selectedRange().location
        guard index < storage.length else { return }
        let text = storage.string as NSString
        let character = text.character(at: index)
        guard character != 10, character != 13 else { return }
        let range = text.rangeOfComposedCharacterSequence(at: index)
        layoutManager.addTemporaryAttribute(.foregroundColor, value: Theme.cursorText, forCharacterRange: range)
        cursorTextRange = range
    }

    private func clearCursorText() {
        guard let range = cursorTextRange, let layoutManager, let storage = textStorage else { return }
        cursorTextRange = nil
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        if clamped.length > 0 {
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: clamped)
        }
    }

    private func startDisplayLink() {
        guard displayLinkRef == nil else { return }
        guard window != nil else {
            _ = smear.step(dt: 10)
            return
        }
        let link = displayLink(target: self, selector: #selector(displayTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLinkRef = link
        lastTick = 0
    }

    @objc private func displayTick(_ link: CADisplayLink) {
        let dt = lastTick == 0 ? 1.0 / 60 : min(link.timestamp - lastTick, 1.0 / 20)
        lastTick = link.timestamp
        let before = smear.bounds
        let running = smear.step(dt: dt)
        invalidate(before.union(smear.bounds))
        if !running {
            link.invalidate()
            displayLinkRef = nil
            applyCursorText()
        }
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        // The smear cursor replaces the system caret.
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        drawDecorations(dirtyRect)
        super.draw(dirtyRect)
        drawPlaceholder(dirtyRect)
    }

    /// Everything that sits behind the glyphs: block backgrounds, quote bars,
    /// rules, inline code, search hits and the cursor itself.
    private func drawDecorations(_ dirty: NSRect) {
        guard let storage = textStorage, let textContainer else { return }
        let origin = textContainerOrigin
        let width = textContainer.size.width
        let all = NSRange(location: 0, length: storage.length)

        for block in codeBlocks {
            guard let r = fragmentsRect(block.range) else { continue }
            let rect = NSRect(x: origin.x - Theme.codeBlockOutset, y: origin.y + r.minY,
                              width: width + Theme.codeBlockOutset * 2, height: r.height)
            guard rect.intersects(dirty) else { continue }
            Theme.codeBlockBackground.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7.5, yRadius: 7.5)
            border.lineWidth = 1
            Theme.codeBlockBorder.setStroke()
            border.stroke()
        }

        storage.enumerateAttribute(.gpQuote, in: all) { value, range, _ in
            guard value != nil, let r = fragmentsRect(range) else { return }
            let bar = NSRect(x: origin.x + 3, y: origin.y + r.minY + 2,
                             width: 2.5, height: r.height - Theme.lineSpacing - 2)
            guard bar.intersects(dirty) else { return }
            Theme.quoteBar.setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1.25, yRadius: 1.25).fill()
        }

        storage.enumerateAttribute(.gpRule, in: all) { value, range, _ in
            guard value != nil, let r = fragmentsRect(range) else { return }
            let y = origin.y + r.minY + (r.height - Theme.lineSpacing) / 2
            let line = NSRect(x: origin.x, y: y.rounded() - 0.5, width: width, height: 1)
            guard line.intersects(dirty) else { return }
            Theme.rule.setFill()
            line.fill()
        }

        storage.enumerateAttribute(.gpInlineCode, in: all) { value, range, _ in
            guard value != nil else { return }
            for rect in textRects(range, padding: 3) where rect.intersects(dirty) {
                Theme.inlineCodeBackground.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            }
        }

        for (i, match) in searchMatches.enumerated() {
            for rect in textRects(match, padding: 1) where rect.intersects(dirty) {
                (i == currentMatch ? Theme.searchCurrent : Theme.searchMatch).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            }
        }

        if smear.isInitialized, !smear.isHidden, smear.bounds.insetBy(dx: -2, dy: -2).intersects(dirty) {
            let path = smear.path()
            if hasFocus {
                Theme.cursor.setFill()
                path.fill()
            } else {
                Theme.cursor.withAlphaComponent(0.5).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
    }

    private func drawPlaceholder(_ dirty: NSRect) {
        guard string.isEmpty, mode != .search else { return }
        let origin = textContainerOrigin
        let offset = mode == .insert ? 6 : Theme.charWidth + 6
        ("Start writing…" as NSString).draw(
            at: NSPoint(x: origin.x + offset, y: origin.y),
            withAttributes: [.font: Theme.font(), .foregroundColor: Theme.placeholder])
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let storage = textStorage {
            let point = convert(event.locationInWindow, from: nil)
            let index = characterIndexForInsertion(at: point)
            if index < storage.length,
               let target = storage.attribute(.gpLink, at: index, effectiveRange: nil) as? String,
               let url = URL(string: target) {
                NSWorkspace.shared.open(url)
                return
            }
        }
        super.mouseDown(with: event)
    }
}
