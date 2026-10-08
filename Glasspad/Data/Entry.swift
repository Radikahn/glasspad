import Foundation

struct Entry: Identifiable, Equatable {
    let id: Int64
    var body: String
    let createdAt: Date
    var updatedAt: Date

    var isBlank: Bool {
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var title: String {
        summaryLines.first ?? "New entry"
    }

    var preview: String {
        summaryLines.dropFirst().first ?? ""
    }

    /// The first couple of readable lines with markdown syntax stripped,
    /// skipping fenced code.
    private var summaryLines: [String] {
        var lines: [String] = []
        var inFence = false
        for raw in body.split(separator: "\n", omittingEmptySubsequences: true).prefix(40) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence { continue }
            let clean = Self.strip(line)
            if !clean.isEmpty { lines.append(clean) }
            if lines.count == 2 { break }
        }
        return lines
    }

    private static let prefixPattern = try! NSRegularExpression(
        pattern: #"^(#{1,6}\s+|>\s?|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+)"#)
    private static let linkPattern = try! NSRegularExpression(pattern: #"!?\[([^\]]*)\]\([^)]*\)"#)
    private static let markerPattern = try! NSRegularExpression(pattern: #"(\*\*|__|~~|`|\*)"#)

    private static func strip(_ line: String) -> String {
        var s = line
        for (regex, template) in [(prefixPattern, ""), (linkPattern, "$1"), (markerPattern, "")] {
            s = regex.stringByReplacingMatches(
                in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
        }
        if s.allSatisfy({ "-*_ ".contains($0) }) { return "" }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
