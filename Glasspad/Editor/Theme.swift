import AppKit
import CoreText

enum Theme {
    // MARK: Metrics

    static let bodySize: CGFloat = 14
    static let codeSize: CGFloat = 13
    static let fenceSize: CGFloat = 11
    static let lineSpacing: CGFloat = 4
    static let codeLineSpacing: CGFloat = 2
    static let textInset = NSSize(width: 26, height: 10)
    static let codeBlockOutset: CGFloat = 8
    static let codeTextIndent: CGFloat = 6
    static let codeBlockMargin: CGFloat = 8
    static let codeFencePadding: CGFloat = 4
    static let quoteIndent: CGFloat = 16

    static func headingSize(_ level: Int) -> CGFloat {
        [22, 18.5, 16, 15, 14, 14][min(max(level, 1), 6) - 1]
    }

    // MARK: Colors

    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }

    static let text = rgb(0xE9E4F5)
    static let heading = rgb(0xF7F2FF)
    static let marker = NSColor(white: 1, alpha: 0.28)
    static let accent = rgb(0xC3A6FF)
    static let link = rgb(0xB7A6FF)
    static let quoteText = rgb(0xC9C1DB)
    static let quoteBar = rgb(0xA98BF0, 0.7)
    static let inlineCode = rgb(0xF2AACF)
    static let inlineCodeBackground = NSColor(white: 1, alpha: 0.07)
    static let codeBlockBackground = rgb(0x0C0616, 0.40)
    static let codeBlockBorder = NSColor(white: 1, alpha: 0.07)
    static let codeText = rgb(0xDDD7EB)
    static let rule = NSColor(white: 1, alpha: 0.14)
    static let doneText = NSColor(white: 1, alpha: 0.38)
    static let cursor = rgb(0xD4C1FF)
    static let cursorText = rgb(0x1A0F2B)
    static let selection = rgb(0x9C7CFF, 0.32)
    static let searchMatch = rgb(0xFFCF70, 0.20)
    static let searchCurrent = rgb(0xFFCF70, 0.42)
    static let placeholder = NSColor(white: 1, alpha: 0.22)

    static let synKeyword = rgb(0xC792EA)
    static let synString = rgb(0xC3E88D)
    static let synNumber = rgb(0xF78C6C)
    static let synComment = rgb(0x7F7A99)
    static let synType = rgb(0xFFCB6B)
    static let synFunction = rgb(0x82AAFF)
    static let synProperty = rgb(0x89DDFF)
    static let synTag = rgb(0xF07178)

    static func color(for token: TokenKind) -> NSColor {
        switch token {
        case .keyword: synKeyword
        case .string: synString
        case .number, .constant: synNumber
        case .comment: synComment
        case .type, .attribute: synType
        case .function: synFunction
        case .property: synProperty
        case .tag: synTag
        }
    }

    // MARK: Fonts

    private static var fontCache: [String: NSFont] = [:]

    static func registerFonts() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func font(size: CGFloat = bodySize, bold: Bool = false, italic: Bool = false) -> NSFont {
        let key = "\(size)-\(bold)-\(italic)"
        if let cached = fontCache[key] { return cached }
        let name = switch (bold, italic) {
        case (false, false): "JetBrainsMono-Regular"
        case (true, false): "JetBrainsMono-Bold"
        case (false, true): "JetBrainsMono-Italic"
        case (true, true): "JetBrainsMono-BoldItalic"
        }
        var font = NSFont(name: name, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
        if italic, NSFont(name: name, size: size) == nil {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        fontCache[key] = font
        return font
    }

    static let charWidth: CGFloat = ("0" as NSString).size(withAttributes: [.font: font()]).width

    // MARK: Paragraphs

    static func paragraph(lineSpacing: CGFloat = Theme.lineSpacing,
                          before: CGFloat = 0,
                          after: CGFloat = 0,
                          indent: CGFloat = 0,
                          tailIndent: CGFloat = 0) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = lineSpacing
        p.paragraphSpacingBefore = before
        p.paragraphSpacing = after
        p.firstLineHeadIndent = indent
        p.headIndent = indent
        p.tailIndent = tailIndent
        p.tabStops = []
        p.defaultTabInterval = charWidth * 4
        return p
    }

    static let bodyParagraph: NSParagraphStyle = paragraph()
    static let quoteParagraph: NSParagraphStyle = paragraph(indent: quoteIndent)
    static let codeParagraph: NSParagraphStyle = paragraph(
        lineSpacing: codeLineSpacing, indent: codeTextIndent, tailIndent: -codeTextIndent)
    /// Fence lines carry the block's inner padding, so a revealed ``` never touches the edge.
    static let codeOpenFenceParagraph: NSParagraphStyle = paragraph(
        lineSpacing: codeLineSpacing, before: codeFencePadding, indent: codeTextIndent, tailIndent: -codeTextIndent)
    static let codeCloseFenceParagraph: NSParagraphStyle = paragraph(
        lineSpacing: codeLineSpacing, after: codeFencePadding, indent: codeTextIndent, tailIndent: -codeTextIndent)

    static func headingParagraph(_ level: Int) -> NSParagraphStyle {
        paragraph(lineSpacing: 2, before: level == 1 ? 8 : 6, after: 2)
    }

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font(), .foregroundColor: text, .paragraphStyle: bodyParagraph]
    }
}
