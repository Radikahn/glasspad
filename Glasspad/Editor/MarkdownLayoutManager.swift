import AppKit

/// Collapses hidden markdown syntax to zero-width glyphs and swaps list
/// markers for bullets, without touching the underlying text.
final class MarkdownLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    private var bulletGlyphs: [String: CGGlyph] = [:]

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    private func bulletGlyph(for font: NSFont) -> CGGlyph? {
        let key = "\(font.fontName)-\(font.pointSize)"
        if let cached = bulletGlyphs[key] { return cached == 0 ? nil : cached }
        var character: UniChar = 0x2022
        var glyph: CGGlyph = 0
        CTFontGetGlyphsForCharacters(font as CTFont, &character, &glyph, 1)
        bulletGlyphs[key] = glyph
        return glyph == 0 ? nil : glyph
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes charIndexes: UnsafePointer<Int>,
                       font aFont: NSFont,
                       forGlyphRange glyphRange: NSRange) -> Int {
        guard let storage = layoutManager.textStorage else { return 0 }
        let count = glyphRange.length
        var newGlyphs: [CGGlyph]?
        var newProps: [NSLayoutManager.GlyphProperty]?

        for i in 0..<count {
            let index = charIndexes[i]
            guard index < storage.length else { continue }
            if storage.attribute(.gpHidden, at: index, effectiveRange: nil) != nil {
                // Marked as a control character so the delegate below can give it zero
                // advancement. (`.null` glyphs at the start of a line make the typesetter
                // emit an empty line fragment.)
                if newProps == nil { newProps = Array(UnsafeBufferPointer(start: props, count: count)) }
                newProps![i] = .controlCharacter
            } else if storage.attribute(.gpBullet, at: index, effectiveRange: nil) != nil,
                      let bullet = bulletGlyph(for: aFont) {
                if newGlyphs == nil { newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: count)) }
                newGlyphs![i] = bullet
            }
        }

        guard newGlyphs != nil || newProps != nil else { return 0 }
        let finalGlyphs = newGlyphs ?? Array(UnsafeBufferPointer(start: glyphs, count: count))
        let finalProps = newProps ?? Array(UnsafeBufferPointer(start: props, count: count))
        finalGlyphs.withUnsafeBufferPointer { g in
            finalProps.withUnsafeBufferPointer { p in
                layoutManager.setGlyphs(g.baseAddress!, properties: p.baseAddress!,
                                        characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
            }
        }
        return count
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        if let storage = layoutManager.textStorage, charIndex < storage.length,
           storage.attribute(.gpHidden, at: charIndex, effectiveRange: nil) != nil {
            return .zeroAdvancement
        }
        return action
    }
}
