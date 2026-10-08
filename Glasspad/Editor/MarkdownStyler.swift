import AppKit

extension NSAttributedString.Key {
    /// Markdown syntax that is collapsed (zero-width) while its line isn't being edited.
    static let gpHidden = NSAttributedString.Key("glasspad.hidden")
    /// A list marker drawn as a bullet glyph.
    static let gpBullet = NSAttributedString.Key("glasspad.bullet")
    static let gpInlineCode = NSAttributedString.Key("glasspad.inlineCode")
    static let gpQuote = NSAttributedString.Key("glasspad.quote")
    static let gpRule = NSAttributedString.Key("glasspad.rule")
    static let gpLink = NSAttributedString.Key("glasspad.link")
}

struct CodeBlock {
    /// Opening fence through closing fence, including the trailing newline.
    var range: NSRange
    var language: String
    /// Where the info string sits on the opening fence (zero-length if none).
    var languageRange: NSRange
    var isClosed: Bool
}

/// Applies live-preview styling to the whole document. Syntax markers on the
/// paragraph(s) touched by `active` stay visible (dimmed) so they can be
/// edited; everywhere else they are hidden and only the rendered text shows.
enum MarkdownStyler {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    private static let fenceOpen = regex(#"^[ \t]{0,3}(`{3,}|~{3,})[ \t]*([^\s`]*)[^`]*$"#)
    private static let fenceClose = regex(#"^[ \t]{0,3}(`{3,}|~{3,})[ \t]*$"#)
    private static let heading = regex(#"^(#{1,6})([ \t]+)(.*)$"#)
    private static let rule = regex(#"^[ \t]{0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    private static let quote = regex(#"^[ \t]{0,3}>[ \t]?"#)
    private static let task = regex(#"^([ \t]*)([-*+])([ \t]+)(\[[ xX]\])(?=[ \t]|$)"#)
    private static let bullet = regex(#"^([ \t]*)([-*+])([ \t]+)"#)
    private static let ordered = regex(#"^([ \t]*)(\d{1,9}[.)])([ \t]+)"#)
    private static let codeSpan = regex(#"(`)([^`]+)(`)"#)
    private static let link = regex(#"(!?\[)([^\]]+)(\]\(([^)\s]+)(?:[ \t]+"[^"]*")?\))"#)
    private static let autolink = regex(#"https?://[^\s<>()\[\]]*[^\s<>()\[\].,;:!?'"]"#)
    private static let emphasis: [(regex: NSRegularExpression, bold: Bool, italic: Bool, strike: Bool)] = [
        (regex(#"(\*\*\*|___)(?=\S)(.+?)(?<=\S)(\1)"#), true, true, false),
        (regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)(\1)"#), true, false, false),
        (regex(#"(\*)(?=[^\s*])(.+?)(?<=[^\s*])(\*)"#), false, true, false),
        (regex(#"(?<![\w])(_)(?=[^\s_])(.+?)(?<=[^\s_])(_)(?![\w])"#), false, true, false),
        (regex(#"(~~)(?=\S)(.+?)(?<=\S)(~~)"#), false, false, true),
    ]

    @discardableResult
    static func style(_ storage: NSTextStorage, active: NSRange) -> [CodeBlock] {
        let string = storage.string
        let text = string as NSString
        let length = text.length

        storage.beginEditing()
        storage.setAttributes(Theme.baseAttributes, range: NSRange(location: 0, length: length))

        var blocks: [CodeBlock] = []
        var open: (line: NSRange, fence: String, language: String, languageRange: NSRange)?
        var position = 0

        while position < length {
            let line = text.lineRange(for: NSRange(location: position, length: 0))
            let content = contentRange(of: line, in: text)
            position = NSMaxRange(line)

            if let fence = open {
                if isClosingFence(string, content, matching: fence.fence) {
                    let range = NSRange(location: fence.line.location, length: NSMaxRange(line) - fence.line.location)
                    let block = CodeBlock(range: range, language: fence.language,
                                          languageRange: fence.languageRange, isClosed: true)
                    styleCodeBlock(storage, text, block, openLine: fence.line, closeLine: line, active: active)
                    blocks.append(block)
                    open = nil
                }
                continue
            }
            if let m = fenceOpen.firstMatch(in: string, range: content) {
                open = (line, text.substring(with: m.range(at: 1)),
                        text.substring(with: m.range(at: 2)), m.range(at: 2))
                continue
            }
            styleLine(storage, string, content: content, line: line, active: intersects(line, active))
        }

        if let fence = open {
            let range = NSRange(location: fence.line.location, length: length - fence.line.location)
            let block = CodeBlock(range: range, language: fence.language,
                                  languageRange: fence.languageRange, isClosed: false)
            styleCodeBlock(storage, text, block, openLine: fence.line, closeLine: nil, active: active)
            blocks.append(block)
        }

        addBlockMargins(storage, text, blocks)
        storage.endEditing()
        return blocks
    }

    // MARK: Helpers

    private static func contentRange(of line: NSRange, in text: NSString) -> NSRange {
        var end = NSMaxRange(line)
        while end > line.location {
            let c = text.character(at: end - 1)
            guard c == 10 || c == 13 else { break }
            end -= 1
        }
        return NSRange(location: line.location, length: end - line.location)
    }

    private static func intersects(_ range: NSRange, _ active: NSRange) -> Bool {
        if NSIntersectionRange(range, active).length > 0 { return true }
        return active.length == 0 && NSLocationInRange(active.location, range)
    }

    private static func isClosingFence(_ string: String, _ content: NSRange, matching fence: String) -> Bool {
        guard let m = fenceClose.firstMatch(in: string, range: content) else { return false }
        let candidate = (string as NSString).substring(with: m.range(at: 1))
        return candidate.first == fence.first && candidate.count >= fence.count
    }

    /// Dim a syntax marker on the active line, collapse it everywhere else.
    private static func mark(_ s: NSTextStorage, _ range: NSRange, _ active: Bool) {
        guard range.location != NSNotFound, range.length > 0 else { return }
        if active {
            s.addAttribute(.foregroundColor, value: Theme.marker, range: range)
        } else {
            s.addAttribute(.gpHidden, value: true, range: range)
        }
    }

    private static func addTraits(_ s: NSTextStorage, _ range: NSRange, bold: Bool, italic: Bool) {
        s.enumerateAttribute(.font, in: range) { value, sub, _ in
            let font = value as? NSFont ?? Theme.font()
            let traits = font.fontDescriptor.symbolicTraits
            s.addAttribute(.font, value: Theme.font(size: font.pointSize,
                                                    bold: bold || traits.contains(.bold),
                                                    italic: italic || traits.contains(.italic)), range: sub)
        }
    }

    private static func setHangingIndent(_ s: NSTextStorage, line: NSRange, prefixWidth: CGFloat) {
        let existing = s.attribute(.paragraphStyle, at: line.location, effectiveRange: nil) as? NSParagraphStyle
        let style = (existing ?? Theme.bodyParagraph).mutableCopy() as! NSMutableParagraphStyle
        style.headIndent = style.firstLineHeadIndent + prefixWidth
        s.addAttribute(.paragraphStyle, value: style, range: line)
    }

    private static func after(_ match: NSRange, in range: NSRange) -> NSRange {
        let start = NSMaxRange(match)
        return NSRange(location: start, length: max(0, NSMaxRange(range) - start))
    }

    // MARK: Block elements

    private static func styleLine(_ s: NSTextStorage, _ string: String, content: NSRange, line: NSRange, active: Bool) {
        guard content.length > 0 else { return }

        if rule.firstMatch(in: string, range: content) != nil {
            s.addAttribute(.gpRule, value: true, range: line)
            mark(s, content, active)
            return
        }

        if let m = heading.firstMatch(in: string, range: content) {
            let level = m.range(at: 1).length
            s.addAttributes([
                .font: Theme.font(size: Theme.headingSize(level), bold: true),
                .foregroundColor: Theme.heading,
                .paragraphStyle: Theme.headingParagraph(level),
            ], range: line)
            mark(s, NSUnionRange(m.range(at: 1), m.range(at: 2)), active)
            styleInline(s, string, m.range(at: 3), active: active)
            return
        }

        var rest = content
        var quoteOffset: CGFloat = 0
        if let m = quote.firstMatch(in: string, range: content) {
            s.addAttributes([
                .gpQuote: true,
                .foregroundColor: Theme.quoteText,
                .font: Theme.font(italic: true),
                .paragraphStyle: Theme.quoteParagraph,
            ], range: line)
            mark(s, m.range, active)
            rest = after(m.range, in: content)
            quoteOffset = active ? CGFloat(m.range.length) * Theme.charWidth : 0
        }

        if let m = task.firstMatch(in: string, range: rest) {
            let marker = NSUnionRange(m.range(at: 2), m.range(at: 3))
            let box = m.range(at: 4)
            if active {
                s.addAttribute(.foregroundColor, value: Theme.accent, range: m.range(at: 2))
            } else {
                s.addAttribute(.gpHidden, value: true, range: marker)
            }
            s.addAttribute(.foregroundColor, value: Theme.accent, range: box)
            let body = after(m.range, in: rest)
            if (string as NSString).substring(with: box).lowercased() == "[x]", body.length > 0 {
                s.addAttributes([
                    .foregroundColor: Theme.doneText,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: Theme.doneText,
                ], range: body)
            }
            let visible = m.range.length - (active ? 0 : marker.length) + 1
            setHangingIndent(s, line: line, prefixWidth: quoteOffset + CGFloat(visible) * Theme.charWidth)
            rest = body
        } else if let m = bullet.firstMatch(in: string, range: rest) {
            let marker = m.range(at: 2)
            s.addAttribute(.foregroundColor, value: Theme.accent, range: marker)
            if !active { s.addAttribute(.gpBullet, value: true, range: marker) }
            setHangingIndent(s, line: line, prefixWidth: quoteOffset + CGFloat(m.range.length) * Theme.charWidth)
            rest = after(m.range, in: rest)
        } else if let m = ordered.firstMatch(in: string, range: rest) {
            s.addAttribute(.foregroundColor, value: Theme.accent, range: m.range(at: 2))
            setHangingIndent(s, line: line, prefixWidth: quoteOffset + CGFloat(m.range.length) * Theme.charWidth)
            rest = after(m.range, in: rest)
        }

        styleInline(s, string, rest, active: active)
    }

    // MARK: Inline elements

    private static func styleInline(_ s: NSTextStorage, _ string: String, _ range: NSRange, active: Bool) {
        guard range.length > 0 else { return }
        var protected = IndexSet()
        var consumed = IndexSet()

        func isFree(_ r: NSRange) -> Bool {
            guard let span = Range(r) else { return false }
            return !protected.intersects(integersIn: span) && !consumed.intersects(integersIn: span)
        }
        func protect(_ r: NSRange) {
            if let span = Range(r) { protected.insert(integersIn: span) }
        }

        for m in codeSpan.matches(in: string, range: range) where isFree(m.range) {
            s.addAttributes([.foregroundColor: Theme.inlineCode, .gpInlineCode: true], range: m.range(at: 2))
            mark(s, m.range(at: 1), active)
            mark(s, m.range(at: 3), active)
            protect(m.range)
        }

        for m in link.matches(in: string, range: range) where isFree(m.range) {
            let url = (string as NSString).substring(with: m.range(at: 4))
            s.addAttributes([
                .foregroundColor: Theme.link,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: Theme.link.withAlphaComponent(0.35),
                .gpLink: url,
            ], range: m.range(at: 2))
            mark(s, m.range(at: 1), active)
            mark(s, m.range(at: 3), active)
            protect(m.range(at: 1))
            protect(m.range(at: 3))
        }

        for m in autolink.matches(in: string, range: range) where isFree(m.range) {
            s.addAttributes([
                .foregroundColor: Theme.link,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: Theme.link.withAlphaComponent(0.35),
                .gpLink: (string as NSString).substring(with: m.range),
            ], range: m.range)
            protect(m.range)
        }

        let end = NSMaxRange(range)
        for style in emphasis {
            // Scan with firstMatch so a rejected match (e.g. one that borrows a `*` from
            // `**bold**`) doesn't swallow a valid match that starts inside it.
            var location = range.location
            while location < end,
                  let m = style.regex.firstMatch(in: string, options: .withTransparentBounds,
                                                 range: NSRange(location: location, length: end - location)) {
                let open = m.range(at: 1), inner = m.range(at: 2), close = m.range(at: 3)
                guard isFree(open), isFree(close) else {
                    location = m.range.location + 1
                    continue
                }
                location = NSMaxRange(m.range)
                if style.bold || style.italic {
                    addTraits(s, inner, bold: style.bold, italic: style.italic)
                }
                if style.strike {
                    s.addAttributes([
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .strikethroughColor: Theme.marker,
                    ], range: inner)
                }
                mark(s, open, active)
                mark(s, close, active)
                if let o = Range(open) { consumed.insert(integersIn: o) }
                if let c = Range(close) { consumed.insert(integersIn: c) }
            }
        }
    }

    // MARK: Code blocks

    private static func styleCodeBlock(_ s: NSTextStorage, _ text: NSString, _ block: CodeBlock,
                                       openLine: NSRange, closeLine: NSRange?, active: NSRange) {
        s.addAttributes([
            .font: Theme.font(size: Theme.codeSize),
            .foregroundColor: Theme.codeText,
            .paragraphStyle: Theme.codeParagraph,
        ], range: block.range)

        // Like every other marker, a fence only shows its raw text while the cursor is
        // on that line; editing inside the block leaves it collapsed.
        let fences = [(openLine, Theme.codeOpenFenceParagraph), (closeLine, Theme.codeCloseFenceParagraph)]
        for case let (fence?, paragraph) in fences {
            s.addAttributes([
                .font: Theme.font(size: Theme.fenceSize),
                .foregroundColor: Theme.marker,
                .paragraphStyle: paragraph,
            ], range: fence)
            if !intersects(fence, active) {
                s.addAttribute(.gpHidden, value: true, range: contentRange(of: fence, in: text))
            } else if fence == openLine, block.languageRange.length > 0 {
                s.addAttribute(.foregroundColor, value: Theme.accent.withAlphaComponent(0.7), range: block.languageRange)
            }
        }

        let bodyStart = NSMaxRange(openLine)
        let bodyEnd = closeLine?.location ?? NSMaxRange(block.range)
        guard bodyEnd > bodyStart else { return }
        let body = NSRange(location: bodyStart, length: bodyEnd - bodyStart)
        let codeFont = Theme.font(size: Theme.codeSize, italic: true)
        for token in SyntaxHighlighter.tokens(in: text.substring(with: body), language: block.language) {
            let range = NSRange(location: body.location + token.range.location, length: token.range.length)
            guard NSMaxRange(range) <= NSMaxRange(body) else { continue }
            s.addAttribute(.foregroundColor, value: Theme.color(for: token.kind), range: range)
            if token.kind == .comment {
                s.addAttribute(.font, value: codeFont, range: range)
            }
        }
    }

    /// Give code blocks breathing room by padding the neighbouring paragraphs,
    /// so the block's own line fragments stay tight around its background.
    private static func addBlockMargins(_ s: NSTextStorage, _ text: NSString, _ blocks: [CodeBlock]) {
        func adjust(_ location: Int, _ change: (NSMutableParagraphStyle) -> Void) {
            guard location >= 0, location < text.length,
                  !blocks.contains(where: { NSLocationInRange(location, $0.range) }) else { return }
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            let existing = s.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            let style = (existing ?? Theme.bodyParagraph).mutableCopy() as! NSMutableParagraphStyle
            change(style)
            s.addAttribute(.paragraphStyle, value: style, range: paragraph)
        }
        for block in blocks {
            adjust(block.range.location - 1) { $0.paragraphSpacing = max($0.paragraphSpacing, Theme.codeBlockMargin) }
            adjust(NSMaxRange(block.range)) { $0.paragraphSpacingBefore = max($0.paragraphSpacingBefore, Theme.codeBlockMargin) }
        }
    }
}
