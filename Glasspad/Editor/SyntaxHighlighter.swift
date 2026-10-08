import Foundation

/// A small single-pass tokenizer. It is not a parser — it just recognises
/// comments, strings, numbers, keywords and a few identifier shapes, which is
/// plenty for journal snippets.
enum SyntaxHighlighter {
    typealias Token = (range: NSRange, kind: TokenKind)

    static func tokens(in code: String, language: String) -> [Token] {
        guard let lang = CodeLanguage.find(language) else { return [] }
        let units = Array(code.utf16)
        return lang.spec.markup ? scanMarkup(units) : scan(units, lang.spec)
    }

    // MARK: Character classes

    private static func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
    private static func isUpper(_ c: UInt16) -> Bool { c >= 65 && c <= 90 }
    private static func isIdentStart(_ c: UInt16) -> Bool {
        isUpper(c) || (c >= 97 && c <= 122) || c == 95 || c > 127
    }
    private static func isIdent(_ c: UInt16) -> Bool { isIdentStart(c) || isDigit(c) }
    private static func isSpace(_ c: UInt16) -> Bool { c == 32 || c == 9 }

    private static func units(_ s: String) -> [UInt16] { Array(s.utf16) }

    private static func has(_ p: [UInt16], in s: [UInt16], at i: Int) -> Bool {
        guard !p.isEmpty, i + p.count <= s.count else { return false }
        for k in 0..<p.count where s[i + k] != p[k] { return false }
        return true
    }

    private static func nextNonSpace(_ s: [UInt16], _ i: Int) -> UInt16? {
        var j = i
        while j < s.count, isSpace(s[j]) { j += 1 }
        return j < s.count ? s[j] : nil
    }

    // MARK: Code

    private static func scan(_ s: [UInt16], _ spec: LanguageSpec) -> [Token] {
        var out: [Token] = []
        let n = s.count
        let lineComments = spec.lineComments.map(units)
        let block = spec.blockComment.map { (units($0.open), units($0.close)) }
        let multiQuotes = spec.multilineQuotes.map(units)
        let quotes = spec.quotes.map(units)
        let varPrefixes = Set(spec.variablePrefixes.compactMap { $0.utf16.first })
        let identExtras = Set(spec.identifierExtras.compactMap { $0.utf16.first })
        var atLineStart = true
        var i = 0

        func emit(_ start: Int, _ kind: TokenKind) {
            out.append((NSRange(location: start, length: min(i, n) - start), kind))
        }

        while i < n {
            let c = s[i]
            if c == 10 { atLineStart = true; i += 1; continue }
            if isSpace(c) { i += 1; continue }
            let lineStart = atLineStart
            atLineStart = false
            let start = i

            if let (open, close) = block, has(open, in: s, at: i) {
                i += open.count
                while i < n, !has(close, in: s, at: i) { i += 1 }
                i = min(n, i + close.count)
                emit(start, .comment)
                continue
            }
            if lineComments.contains(where: { has($0, in: s, at: i) }),
               c != 35 || i == 0 || !(isIdent(s[i - 1]) || s[i - 1] == 36) {
                while i < n, s[i] != 10 { i += 1 }
                emit(start, .comment)
                continue
            }
            if spec.preprocessor, lineStart, c == 35 {
                i += 1
                while i < n, isIdent(s[i]) { i += 1 }
                emit(start, .keyword)
                continue
            }
            if let q = multiQuotes.first(where: { has($0, in: s, at: i) }) {
                i += q.count
                while i < n, !has(q, in: s, at: i) { i += s[i] == 92 ? 2 : 1 }
                i = min(n, i + q.count)
                emit(start, .string)
                continue
            }
            if let q = quotes.first(where: { has($0, in: s, at: i) }) {
                i += q.count
                while i < n, s[i] != 10, !has(q, in: s, at: i) { i += s[i] == 92 ? 2 : 1 }
                if i < n, has(q, in: s, at: i) { i += q.count }
                let isKey = spec.keyColon && nextNonSpace(s, min(i, n)) == 58
                emit(start, isKey ? .property : .string)
                continue
            }
            if isDigit(c) {
                while i < n, isIdent(s[i]) || s[i] == 46 { i += 1 }
                emit(start, .number)
                continue
            }
            if varPrefixes.contains(c), i + 1 < n, isIdentStart(s[i + 1]) || s[i + 1] == 123 {
                i += 1
                if s[i] == 123 {
                    while i < n, s[i] != 125, s[i] != 10 { i += 1 }
                    if i < n, s[i] == 125 { i += 1 }
                } else {
                    while i < n, isIdent(s[i]) { i += 1 }
                }
                emit(start, .property)
                continue
            }
            if c == 64, i + 1 < n, isIdentStart(s[i + 1]) {
                i += 1
                while i < n, isIdent(s[i]) { i += 1 }
                emit(start, .attribute)
                continue
            }
            if isIdentStart(c) {
                while i < n, isIdent(s[i]) || identExtras.contains(s[i]) { i += 1 }
                let word = String(utf16CodeUnits: Array(s[start..<i]), count: i - start)
                let lookup = spec.caseInsensitive ? word.lowercased() : word
                let next = nextNonSpace(s, i)
                if spec.keywords.contains(lookup) {
                    emit(start, .keyword)
                } else if spec.constants.contains(lookup) {
                    emit(start, .constant)
                } else if spec.keyColon, next == 58 {
                    emit(start, .property)
                } else if spec.builtinTypes.contains(word) {
                    emit(start, .type)
                } else if next == 40 {
                    emit(start, .function)
                } else if isUpper(c) {
                    emit(start, .type)
                }
                continue
            }
            i += 1
        }
        return out
    }

    // MARK: Markup

    private static func scanMarkup(_ s: [UInt16]) -> [Token] {
        var out: [Token] = []
        let n = s.count
        let commentOpen = units("<!--"), commentClose = units("-->")
        var i = 0

        while i < n {
            let start = i
            if has(commentOpen, in: s, at: i) {
                i += commentOpen.count
                while i < n, !has(commentClose, in: s, at: i) { i += 1 }
                i = min(n, i + commentClose.count)
                out.append((NSRange(location: start, length: i - start), .comment))
            } else if s[i] == 60, i + 1 < n, isIdentStart(s[i + 1]) || [47, 33, 63].contains(s[i + 1]) {
                i += 1
                if [47, 33, 63].contains(s[i]) { i += 1 }
                let nameStart = i
                while i < n, isIdent(s[i]) || s[i] == 45 || s[i] == 58 { i += 1 }
                out.append((NSRange(location: nameStart, length: i - nameStart), .tag))
                while i < n, s[i] != 62 {
                    if isIdentStart(s[i]) {
                        let attrStart = i
                        while i < n, isIdent(s[i]) || s[i] == 45 || s[i] == 58 { i += 1 }
                        out.append((NSRange(location: attrStart, length: i - attrStart), .attribute))
                    } else if s[i] == 34 || s[i] == 39 {
                        let quote = s[i], strStart = i
                        i += 1
                        while i < n, s[i] != quote { i += 1 }
                        i = min(n, i + 1)
                        out.append((NSRange(location: strStart, length: i - strStart), .string))
                    } else {
                        i += 1
                    }
                }
                i += 1
            } else if s[i] == 38 {
                i += 1
                while i < n, isIdent(s[i]) || s[i] == 35 { i += 1 }
                if i < n, s[i] == 59 { i += 1 }
                out.append((NSRange(location: start, length: i - start), .constant))
            } else {
                i += 1
            }
        }
        return out
    }
}
