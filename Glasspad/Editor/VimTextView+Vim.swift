import AppKit

/// A deliberately small vim: normal / insert / visual modes, hjkl and a few other
/// motions, `/` search, yank and put, plus the handful of edits that make normal
/// mode usable.
extension VimTextView {
    private static let listPrefix = try! NSRegularExpression(
        pattern: #"^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+)(\[[ xX]\][ \t]+)?"#)
    private static let quotePrefix = try! NSRegularExpression(pattern: #"^(?:[ \t]*>[ \t]?)+"#)

    // MARK: Text helpers

    var nsText: NSString { (textStorage?.string ?? "") as NSString }
    var textLength: Int { textStorage?.length ?? 0 }
    /// The cursor position; in visual mode that's the moving end of the selection.
    var cursor: Int { mode.isVisual ? visualHead : selectedRange().location }

    func lineRange(at index: Int) -> NSRange {
        nsText.lineRange(for: NSRange(location: min(max(index, 0), textLength), length: 0))
    }

    func lineStart(_ index: Int) -> Int {
        lineRange(at: index).location
    }

    /// End of the line's text, before its newline.
    func lineContentEnd(_ index: Int) -> Int {
        let range = lineRange(at: index)
        var end = NSMaxRange(range)
        while end > range.location, [10, 13].contains(nsText.character(at: end - 1)) { end -= 1 }
        return end
    }

    func prevIndex(_ index: Int) -> Int {
        index <= 0 ? 0 : nsText.rangeOfComposedCharacterSequence(at: index - 1).location
    }

    func nextIndex(_ index: Int) -> Int {
        index >= textLength ? textLength : NSMaxRange(nsText.rangeOfComposedCharacterSequence(at: index))
    }

    func firstNonBlank(_ index: Int) -> Int {
        var i = lineStart(index)
        let end = lineContentEnd(index)
        while i < end, [32, 9].contains(nsText.character(at: i)) { i += 1 }
        return i
    }

    /// Normal mode sits on a character, never past the end of a non-empty line.
    func clampNormal(_ index: Int) -> Int {
        var i = max(0, min(index, textLength))
        let start = lineStart(i), end = lineContentEnd(i)
        if end == start { return start }
        if i >= end { i = prevIndex(end) }
        if i < textLength { i = nsText.rangeOfComposedCharacterSequence(at: i).location }
        return i
    }

    /// Moves the cursor; in visual mode this moves the selection's head.
    func setCursor(_ index: Int) {
        let index = max(0, min(index, textLength))
        if mode.isVisual {
            visualHead = clampNormal(index)
            applyVisualSelection()
        } else {
            setSelectedRange(NSRange(location: index, length: 0))
        }
        scrollRangeToVisible(NSRange(location: cursor, length: 0))
    }

    private func leadingWhitespace(at index: Int) -> String {
        let start = lineStart(index)
        return nsText.substring(with: NSRange(location: start, length: firstNonBlank(index) - start))
    }

    // MARK: Key dispatch

    override func keyDown(with event: NSEvent) {
        switch mode {
        case .insert:
            if isEscape(event), !hasMarkedText() {
                exitInsertMode()
            } else {
                super.keyDown(with: event)
            }
        case .normal, .visual, .visualLine:
            handleNormal(event)
        case .search:
            handleSearch(event)
        }
    }

    private func isEscape(_ event: NSEvent) -> Bool {
        event.keyCode == 53
            || (event.modifierFlags.contains(.control) && event.charactersIgnoringModifiers == "[")
    }

    private func handleNormal(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { return }
        if isEscape(event) {
            pendingOperator = ""
            countBuffer = ""
            if mode.isVisual { exitVisual() } else { clearSearchHighlights() }
            return
        }
        if flags.contains(.control) {
            if event.charactersIgnoringModifiers == "r", mode == .normal { redoChange() }
            return
        }
        let key: String
        switch event.keyCode {
        case 123: key = "h"
        case 124: key = "l"
        case 125, 36, 76: key = "j"
        case 126: key = "k"
        case 51: key = "h"
        default: key = event.characters ?? ""
        }
        handleNormalKey(key)
    }

    private func handleNormalKey(_ key: String) {
        if pendingOperator.isEmpty, key.count == 1, let digit = key.first, digit.isASCII, digit.isNumber,
           digit != "0" || !countBuffer.isEmpty {
            countBuffer.append(digit)
            return
        }
        let hasCount = !countBuffer.isEmpty
        let count = min(max(Int(countBuffer) ?? 1, 1), 10_000)
        countBuffer = ""

        if !pendingOperator.isEmpty {
            let combo = pendingOperator + key
            pendingOperator = ""
            switch combo {
            case "gg": setCursor(firstNonBlank(lineStartIndex(ofLine: pendingCount)))
            case "dd" where mode == .normal: deleteLines(pendingCount)
            case "yy" where mode == .normal: yankLines(pendingCount)
            default: break
            }
            return
        }

        if performMotion(key, count: count, hasCount: hasCount) { return }
        if key == "g" {
            pendingOperator = key
            pendingCount = count
            return
        }
        if mode.isVisual {
            handleVisualKey(key)
            return
        }

        switch key {
        case "d", "y":
            pendingOperator = key
            pendingCount = count
        case "v": enterVisual(.visual)
        case "V": enterVisual(.visualLine)
        case "i": enterInsert(at: cursor)
        case "a": enterInsert(at: lineContentEnd(cursor) == lineStart(cursor) ? cursor : nextIndex(cursor))
        case "I": enterInsert(at: firstNonBlank(cursor))
        case "A": enterInsert(at: lineContentEnd(cursor))
        case "o": openLine(below: true)
        case "O": openLine(below: false)
        case "x": deleteCharacters(count)
        case "Y": yankLines(count)
        case "p": put(after: true, count: count)
        case "P": put(after: false, count: count)
        case "u": undoChange(count)
        case "/": beginSearch()
        default: break
        }
    }

    /// Motions shared by normal and visual mode. Returns false if `key` isn't one.
    private func performMotion(_ key: String, count: Int, hasCount: Bool) -> Bool {
        switch key {
        case "h": moveHorizontal(-1, count: count)
        case "l", " ": moveHorizontal(1, count: count)
        case "j": moveVertical(1, count: count)
        case "k": moveVertical(-1, count: count)
        case "w": wordForward(count)
        case "b": wordBackward(count)
        case "e": wordEnd(count)
        case "0": setCursor(lineStart(cursor))
        case "^": setCursor(firstNonBlank(cursor))
        case "$": setCursor(lineContentEnd(cursor))
        case "G": setCursor(firstNonBlank(hasCount ? lineStartIndex(ofLine: count) : lineStart(textLength)))
        case "n": jumpToMatch(forward: true, count: count)
        case "N": jumpToMatch(forward: false, count: count)
        default: return false
        }
        return true
    }

    // MARK: Motions

    private func moveHorizontal(_ direction: Int, count: Int) {
        var i = cursor
        for _ in 0..<count {
            if direction < 0 {
                guard i > lineStart(i) else { break }
                i = prevIndex(i)
            } else {
                let next = nextIndex(i)
                guard next < lineContentEnd(i) else { break }
                i = next
            }
        }
        setCursor(i)
    }

    /// j/k move by visual (wrapped) line, keeping the cursor's column.
    private func moveVertical(_ direction: Int, count: Int) {
        guard let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let x = goalX ?? (caretRect(for: cursor, block: true).minX - textContainerOrigin.x + 1)
        var index = cursor
        for _ in 0..<count {
            guard let next = indexOnAdjacentLine(from: index, direction: direction, x: x) else { break }
            index = next
        }
        preserveGoal = true
        setCursor(index)
        preserveGoal = false
        goalX = x
    }

    private func indexOnAdjacentLine(from index: Int, direction: Int, x: CGFloat) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        let length = textLength
        let extra = layoutManager.extraLineFragmentRect
        let current: NSRect
        if index >= length, length == 0 || nsText.character(at: length - 1) == 10 {
            current = extra
        } else {
            let glyph = layoutManager.glyphIndexForCharacter(at: min(index, length - 1))
            current = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        }
        let y = direction > 0 ? current.maxY + 1 : current.minY - 1
        guard y >= 0 else { return nil }
        if !extra.isEmpty, y >= extra.minY, y < extra.maxY { return length }
        guard y <= layoutManager.usedRect(for: textContainer).maxY else { return nil }
        var fraction: CGFloat = 0
        return layoutManager.characterIndex(
            for: NSPoint(x: x, y: y), in: textContainer, fractionOfDistanceBetweenInsertionPoints: &fraction)
    }

    /// 0 = whitespace, 1 = word, 2 = punctuation.
    private func charClass(_ i: Int) -> Int {
        let c = nsText.character(at: i)
        if [32, 9, 10, 13].contains(c) { return 0 }
        if c == 95 || (48...57).contains(c) || (65...90).contains(c) || (97...122).contains(c) || c > 127 { return 1 }
        return 2
    }

    private func isNewline(_ i: Int) -> Bool {
        i >= 0 && i < textLength && nsText.character(at: i) == 10
    }

    private func wordForward(_ count: Int) {
        let n = textLength
        var i = cursor
        for _ in 0..<count {
            guard i < n else { break }
            let cls = charClass(i)
            if cls != 0 { while i < n, charClass(i) == cls { i += 1 } }
            while i < n, charClass(i) == 0 {
                if isNewline(i), isNewline(i + 1) { i += 1; break }
                i += 1
            }
        }
        setCursor(i)
    }

    private func wordBackward(_ count: Int) {
        var i = cursor
        for _ in 0..<count {
            guard i > 0 else { break }
            i -= 1
            while i > 0, charClass(i) == 0 {
                if isNewline(i), isNewline(i - 1) { break }
                i -= 1
            }
            let cls = charClass(i)
            if cls != 0 { while i > 0, charClass(i - 1) == cls { i -= 1 } }
        }
        setCursor(i)
    }

    private func wordEnd(_ count: Int) {
        let n = textLength
        var i = cursor
        for _ in 0..<count {
            guard i + 1 < n else { break }
            i += 1
            while i < n - 1, charClass(i) == 0 { i += 1 }
            let cls = charClass(i)
            while cls != 0, i + 1 < n, charClass(i + 1) == cls { i += 1 }
        }
        setCursor(i)
    }

    /// Start of the 1-based logical line `number` (or the last line).
    private func lineStartIndex(ofLine number: Int) -> Int {
        var index = 0
        var line = 1
        while line < number {
            let next = NSMaxRange(lineRange(at: index))
            guard next < textLength || (next == textLength && next > index && isNewline(next - 1)) else { break }
            index = next
            line += 1
        }
        return index
    }

    // MARK: Edits

    private func enterInsert(at index: Int) {
        breakUndoCoalescing()
        mode = .insert
        setCursor(index)
    }

    func exitInsertMode() {
        breakUndoCoalescing()
        let i = cursor
        mode = .normal
        setCursor(i > lineStart(i) ? prevIndex(i) : i)
    }

    private func openLine(below: Bool) {
        let i = cursor
        let indent = leadingWhitespace(at: i)
        let indentLength = (indent as NSString).length
        breakUndoCoalescing()
        mode = .insert
        if below {
            let at = lineContentEnd(i)
            replaceText(in: NSRange(location: at, length: 0), with: "\n" + indent)
            setCursor(at + 1 + indentLength)
        } else {
            let at = lineStart(i)
            replaceText(in: NSRange(location: at, length: 0), with: indent + "\n")
            setCursor(at + indentLength)
        }
    }

    private func deleteCharacters(_ count: Int) {
        let start = cursor
        let end = lineContentEnd(start)
        guard start < end else { return }
        var stop = start
        for _ in 0..<count where stop < end { stop = nextIndex(stop) }
        let range = NSRange(location: start, length: stop - start)
        yank(nsText.substring(with: range), linewise: false)
        breakUndoCoalescing()
        replaceText(in: range, with: "")
        setCursor(start)
    }

    private func deleteLines(_ count: Int) {
        let start = lineStart(cursor)
        var end = start
        for _ in 0..<count where end < textLength { end = NSMaxRange(lineRange(at: end)) }
        var range = NSRange(location: start, length: end - start)
        let lines = nsText.substring(with: range)
        // Deleting the final line takes the newline before it instead.
        if end >= textLength, start > 0, range.length == 0 || !isNewline(end - 1) {
            range = NSRange(location: start - 1, length: end - start + 1)
        }
        guard range.length > 0 else { return }
        yank(lines.hasSuffix("\n") ? lines : lines + "\n", linewise: true)
        breakUndoCoalescing()
        replaceText(in: range, with: "")
        setCursor(firstNonBlank(min(range.location, textLength)))
    }

    private func undoChange(_ count: Int) {
        guard let undoManager else { return }
        for _ in 0..<count where undoManager.canUndo { undoManager.undo() }
        setCursor(selectedRange().location)
    }

    private func redoChange() {
        guard let undoManager, undoManager.canRedo else { return }
        undoManager.redo()
        setCursor(selectedRange().location)
    }

    // MARK: Visual mode

    /// The selected text: inclusive of the character under the head, or whole lines in V-LINE.
    func visualRange() -> NSRange {
        let low = min(visualAnchor, visualHead), high = max(visualAnchor, visualHead)
        if mode == .visualLine {
            let start = lineStart(low)
            return NSRange(location: start, length: NSMaxRange(lineRange(at: high)) - start)
        }
        let end = min(textLength, nextIndex(high))
        return NSRange(location: low, length: max(0, end - low))
    }

    func applyVisualSelection() {
        setSelectedRange(visualRange())
    }

    private func enterVisual(_ visualMode: VimMode) {
        let here = cursor
        visualAnchor = here
        visualHead = here
        mode = visualMode
        applyVisualSelection()
    }

    private func exitVisual(to index: Int? = nil) {
        let target = index ?? visualHead
        mode = .normal
        setCursor(target)
    }

    private func handleVisualKey(_ key: String) {
        switch key {
        case "v":
            if mode == .visual { exitVisual() } else { mode = .visual; applyVisualSelection() }
        case "V":
            if mode == .visualLine { exitVisual() } else { mode = .visualLine; applyVisualSelection() }
        case "o":
            (visualAnchor, visualHead) = (visualHead, visualAnchor)
            applyVisualSelection()
            scrollRangeToVisible(NSRange(location: visualHead, length: 0))
        case "d", "x": deleteVisual(thenInsert: false)
        case "c", "s": deleteVisual(thenInsert: true)
        case "y": yankVisual()
        case "p", "P": replaceVisual()
        default: break
        }
    }

    private func selectedVisualText() -> (range: NSRange, text: String, linewise: Bool) {
        let range = visualRange()
        let linewise = mode == .visualLine
        var text = nsText.substring(with: range)
        if linewise, !text.hasSuffix("\n") { text += "\n" }
        return (range, text, linewise)
    }

    private func yankVisual() {
        let selection = selectedVisualText()
        if selection.range.length > 0 { yank(selection.text, linewise: selection.linewise) }
        exitVisual(to: min(visualAnchor, visualHead))
    }

    private func deleteVisual(thenInsert: Bool) {
        let selection = selectedVisualText()
        var range = selection.range
        guard range.length > 0 else { return exitVisual() }
        yank(selection.text, linewise: selection.linewise)
        let endsWithNewline = nsText.substring(with: range).hasSuffix("\n")
        breakUndoCoalescing()
        mode = thenInsert ? .insert : .normal
        if selection.linewise, thenInsert {
            // `c` on whole lines leaves one empty line to type into.
            replaceText(in: range, with: endsWithNewline ? "\n" : "")
            setCursor(range.location)
            return
        }
        if selection.linewise, !endsWithNewline, range.location > 0 {
            // The last line has no newline of its own; take the one before it.
            range = NSRange(location: range.location - 1, length: range.length + 1)
        }
        replaceText(in: range, with: "")
        setCursor(selection.linewise ? firstNonBlank(min(range.location, textLength)) : range.location)
    }

    /// `p` over a selection swaps it for the register, which is left as it was.
    private func replaceVisual() {
        guard let contents = registerContents() else { return exitVisual() }
        let selection = selectedVisualText()
        var replacement = contents.text
        if selection.linewise, !replacement.hasSuffix("\n"),
           nsText.substring(with: selection.range).hasSuffix("\n") {
            replacement += "\n"
        }
        breakUndoCoalescing()
        mode = .normal
        replaceText(in: selection.range, with: replacement)
        setCursor(selection.range.location)
    }

    // MARK: Yank & put

    /// Stores text in the register and on the system clipboard.
    func yank(_ text: String, linewise: Bool) {
        guard !text.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        register = YankRegister(text: text, linewise: linewise, changeCount: pasteboard.changeCount)
    }

    /// Our last yank, or whatever was copied elsewhere since (treated as linewise if it
    /// ends in a newline).
    private func registerContents() -> (text: String, linewise: Bool)? {
        if let register, register.changeCount == pasteboard.changeCount {
            return (register.text, register.linewise)
        }
        if let link = ImageStore.markdownLink(from: pasteboard) { return (link + "\n", true) }
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return nil }
        return (text, text.hasSuffix("\n"))
    }

    private func yankLines(_ count: Int) {
        let start = lineStart(cursor)
        var end = start
        for _ in 0..<count where end < textLength { end = NSMaxRange(lineRange(at: end)) }
        let lines = nsText.substring(with: NSRange(location: start, length: end - start))
        yank(lines.hasSuffix("\n") ? lines : lines + "\n", linewise: true)
    }

    private func put(after: Bool, count: Int) {
        guard let contents = registerContents() else { return }
        let text = String(repeating: contents.text, count: count)
        breakUndoCoalescing()

        if contents.linewise {
            let lines = text.hasSuffix("\n") ? text : text + "\n"
            if !after {
                let start = lineStart(cursor)
                replaceText(in: NSRange(location: start, length: 0), with: lines)
                setCursor(firstNonBlank(start))
                return
            }
            let below = NSMaxRange(lineRange(at: cursor))
            if below >= textLength, textLength > 0, !isNewline(textLength - 1) {
                // The last line has no newline yet: start a new line for the paste.
                replaceText(in: NSRange(location: textLength, length: 0), with: "\n" + String(lines.dropLast()))
                setCursor(firstNonBlank(below + 1))
            } else {
                replaceText(in: NSRange(location: below, length: 0), with: lines)
                setCursor(firstNonBlank(below))
            }
            return
        }

        let onEmptyLine = lineContentEnd(cursor) == lineStart(cursor)
        let at = after && !onEmptyLine ? nextIndex(cursor) : cursor
        replaceText(in: NSRange(location: at, length: 0), with: text)
        let end = at + (text as NSString).length
        setCursor(text.contains("\n") ? at : max(at, end - 1))
    }

    // MARK: Insert-mode conveniences

    override func insertNewline(_ sender: Any?) {
        if mode == .insert, !hasMarkedText(), smartNewline() { return }
        super.insertNewline(sender)
    }

    override func insertTab(_ sender: Any?) {
        guard mode == .insert else { return }
        let selection = selectedRange()
        let start = lineStart(selection.location)
        let before = nsText.substring(with: NSRange(location: start, length: selection.location - start))
        if let m = Self.listPrefix.firstMatch(in: before, range: NSRange(location: 0, length: (before as NSString).length)),
           m.range.length == (before as NSString).length {
            replaceText(in: NSRange(location: start, length: 0), with: "  ")
            setCursor(selection.location + 2)
        } else {
            insertText("    ", replacementRange: selection)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        guard mode == .insert else { return }
        let selection = selectedRange()
        let start = lineStart(selection.location)
        var count = 0
        while count < 2, start + count < textLength, nsText.character(at: start + count) == 32 { count += 1 }
        guard count > 0 else { return }
        replaceText(in: NSRange(location: start, length: count), with: "")
        setCursor(max(start, selection.location - count))
    }

    /// Continues lists and quotes, closes code fences and keeps indentation.
    private func smartNewline() -> Bool {
        let selection = selectedRange()
        let start = lineStart(selection.location)
        let end = lineContentEnd(selection.location)
        guard selection.location >= start else { return false }
        let line = nsText.substring(with: NSRange(location: start, length: end - start))
        let before = nsText.substring(with: NSRange(location: start, length: selection.location - start))
        let beforeRange = NSRange(location: 0, length: (before as NSString).length)
        let indent = String(before.prefix { $0 == " " || $0 == "\t" })
        let indentLength = (indent as NSString).length

        if selection.length == 0, selection.location == end,
           codeBlocks.contains(where: { $0.range.location == start }), fenceNeedsClosing(after: end) {
            let fence = line.trimmingCharacters(in: .whitespaces).prefix { $0 == "`" || $0 == "~" }
            insertText("\n" + indent + "\n" + indent + fence, replacementRange: selection)
            setCursor(selection.location + 1 + indentLength)
            return true
        }

        if codeBlocks.contains(where: { NSLocationInRange(selection.location, $0.range) && $0.range.location != start }) {
            insertText("\n" + indent, replacementRange: selection)
            return true
        }

        if let m = Self.listPrefix.firstMatch(in: before, range: beforeRange) {
            let prefix = before as NSString
            let rest = (line as NSString).substring(from: m.range.length)
            if rest.trimmingCharacters(in: .whitespaces).isEmpty {
                replaceText(in: NSRange(location: start, length: end - start), with: "")
                setCursor(start)
                return true
            }
            var marker = prefix.substring(with: m.range(at: 2))
            if let number = Int(marker.dropLast()), let delimiter = marker.last {
                marker = "\(number + 1)\(delimiter)"
            }
            let task = m.range(at: 4).location != NSNotFound ? "[ ] " : ""
            let continuation = "\n" + prefix.substring(with: m.range(at: 1)) + marker
                + prefix.substring(with: m.range(at: 3)) + task
            insertText(continuation, replacementRange: selection)
            return true
        }

        if let m = Self.quotePrefix.firstMatch(in: before, range: beforeRange) {
            let prefix = (before as NSString).substring(with: m.range)
            if (line as NSString).substring(from: m.range.length).trimmingCharacters(in: .whitespaces).isEmpty {
                replaceText(in: NSRange(location: start, length: end - start), with: "")
                setCursor(start)
                return true
            }
            insertText("\n" + prefix, replacementRange: selection)
            return true
        }

        if !indent.isEmpty {
            insertText("\n" + indent, replacementRange: selection)
            return true
        }
        return false
    }

    /// A fence typed above existing code blocks gets paired with *their* closing
    /// fence by the styler, so instead count the fences below: if they are already
    /// balanced, this new one has no partner yet.
    private func fenceNeedsClosing(after location: Int) -> Bool {
        var fences = 0
        nsText.substring(from: location).enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { fences += 1 }
        }
        return fences % 2 == 0
    }

    // MARK: Search

    private func beginSearch() {
        searchOrigin = cursor
        searchQuery = ""
        mode = .search
        publishStatus()
    }

    private func handleSearch(_ event: NSEvent) {
        if isEscape(event) {
            cancelSearch()
            return
        }
        switch event.keyCode {
        case 36, 76:
            if searchQuery.isEmpty, !lastSearch.isEmpty {
                searchQuery = lastSearch
                updateIncrementalSearch()
            }
            lastSearch = searchQuery
            searchQuery = ""
            let target = currentMatch.map { searchMatches[$0].location } ?? searchOrigin
            mode = .normal
            setCursor(target)
            publishStatus()
        case 51:
            if searchQuery.isEmpty {
                cancelSearch()
            } else {
                searchQuery.removeLast()
                updateIncrementalSearch()
            }
        default:
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !flags.contains(.command), !flags.contains(.control),
                  let characters = event.characters, !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({ $0.value >= 32 && !(0xF700...0xF8FF).contains($0.value) })
            else { return }
            searchQuery += characters
            updateIncrementalSearch()
        }
    }

    private func cancelSearch() {
        searchQuery = ""
        searchMatches = []
        currentMatch = nil
        mode = .normal
        setCursor(searchOrigin)
        needsDisplay = true
        publishStatus()
    }

    private func updateIncrementalSearch() {
        searchMatches = findMatches(searchQuery)
        if let index = searchMatches.firstIndex(where: { $0.location > searchOrigin })
            ?? (searchMatches.isEmpty ? nil : 0) {
            currentMatch = index
            setCursor(searchMatches[index].location)
        } else {
            currentMatch = nil
            setCursor(searchOrigin)
        }
        needsDisplay = true
        publishStatus()
    }

    private func jumpToMatch(forward: Bool, count: Int) {
        guard !lastSearch.isEmpty else { return }
        searchMatches = findMatches(lastSearch)
        needsDisplay = true
        guard !searchMatches.isEmpty else {
            currentMatch = nil
            publishStatus()
            return
        }
        var index = cursor
        var target = 0
        for _ in 0..<count {
            if forward {
                target = searchMatches.firstIndex { $0.location > index } ?? 0
            } else {
                target = searchMatches.lastIndex { $0.location < index } ?? searchMatches.count - 1
            }
            index = searchMatches[target].location
        }
        currentMatch = target
        setCursor(index)
        publishStatus()
    }

    private func clearSearchHighlights() {
        guard !searchMatches.isEmpty else { return }
        searchMatches = []
        currentMatch = nil
        needsDisplay = true
        publishStatus()
    }

    /// Keeps highlights in step with edits.
    func refreshSearchMatches() {
        let query = mode == .search ? searchQuery : lastSearch
        guard !searchMatches.isEmpty, !query.isEmpty else { return }
        searchMatches = findMatches(query)
        currentMatch = searchMatches.firstIndex { NSLocationInRange(cursor, $0) }
        publishStatus()
    }

    /// Plain substring search; case-insensitive unless the query has capitals.
    private func findMatches(_ query: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let options: NSString.CompareOptions =
            query.rangeOfCharacter(from: .uppercaseLetters) == nil ? [.caseInsensitive] : []
        let text = nsText
        var results: [NSRange] = []
        var location = 0
        while location < text.length {
            let found = text.range(of: query, options: options,
                                   range: NSRange(location: location, length: text.length - location))
            guard found.location != NSNotFound, found.length > 0 else { break }
            results.append(found)
            location = NSMaxRange(found)
        }
        return results
    }
}
