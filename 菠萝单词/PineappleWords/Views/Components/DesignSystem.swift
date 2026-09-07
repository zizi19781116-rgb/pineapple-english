import SwiftUI
import PineappleCore

enum Palette {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let accent = Color("AccentColor")
}
@MainActor
struct Surface<Content: View>: View {
    var title: String?
    var content: Content
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title { Text(title).font(.headline) }
            content
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
    }
}
@MainActor
struct MetricTile: View {
    var title: String
    var value: String
    var icon: String
    var body: some View {
        Surface {
            Label(title, systemImage: icon).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
                .minimumScaleFactor(0.7).lineLimit(2)
        }
    }
}
@MainActor
struct QuietEmptyState: View {
    var title: String
    var detail: String
    var icon: String = "book.closed"
    var body: some View {
        ContentUnavailableView(title, systemImage: icon, description: Text(detail))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
@MainActor
struct InlineNotice: View {
    var text: String
    var body: some View {
        Label(text, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
@MainActor
struct WordRowView: View {
    var word: Vocabulary
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(word.word).font(.system(.title3, design: .rounded, weight: .medium))
                Text(word.details.coreMeaning.isEmpty ? "尚无中文释义" : word.details.coreMeaning)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            if word.isFavorite { Image(systemName: "bookmark.fill").foregroundStyle(Palette.accent).accessibilityLabel("已收藏") }
            Text(word.progress.masteryLevel.title).font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 7).contentShape(Rectangle())
    }
}
@MainActor
struct FlowText: View {
    var items: [String]
    var body: some View {
        Text(items.joined(separator: "  ·  ")).font(.body).lineSpacing(6).textSelection(.enabled)
    }
}
