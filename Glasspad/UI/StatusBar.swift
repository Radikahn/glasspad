import SwiftUI

struct StatusBar: View {
    let status: EditorStatus

    var body: some View {
        HStack(spacing: 10) {
            switch status.mode {
            case .search:
                HStack(spacing: 0) {
                    Text("/" + status.searchQuery)
                        .foregroundStyle(.white.opacity(0.85))
                    Rectangle()
                        .fill(Color.glassAccent)
                        .frame(width: 1.5, height: 12)
                        .padding(.leading, 1)
                }
            case .insert:
                Text("INSERT")
                    .tracking(1.2)
                    .foregroundStyle(Color.glassAccent.opacity(0.9))
            case .visual, .visualLine:
                Text(status.mode == .visual ? "VISUAL" : "V-LINE")
                    .tracking(1.2)
                    .foregroundStyle(Color.glassAccent.opacity(0.9))
            case .normal:
                Text("NORMAL")
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.32))
                if status.matchCount > 0 {
                    Text("/" + status.searchQuery)
                        .foregroundStyle(.white.opacity(0.32))
                }
            }
            if status.matchCount > 0 || (status.mode == .search && !status.searchQuery.isEmpty) {
                Text(status.matchCount > 0 ? "\(status.matchIndex)/\(status.matchCount)" : "no match")
                    .foregroundStyle(.white.opacity(0.25))
            }
            Spacer()
            Text("\(status.wordCount) \(status.wordCount == 1 ? "word" : "words")")
                .foregroundStyle(.white.opacity(0.22))
        }
        .font(.mono(10))
        .padding(.horizontal, 18)
        .frame(height: 28)
    }
}
