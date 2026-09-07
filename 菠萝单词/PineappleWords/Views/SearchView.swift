import SwiftUI
import PineappleCore

@MainActor
struct SearchView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool
    private var matches: [Vocabulary] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let noteWords = Set(store.snapshot.notes.filter { $0.text.localizedStandardContains(query) }.map(\.wordID))
        let bookIDs = Set(store.snapshot.books.filter { $0.name.localizedStandardContains(query) || $0.description.localizedStandardContains(query) }.map(\.id))
        return store.snapshot.words.filter {
            $0.details.searchableText.localizedStandardContains(query) || noteWords.contains($0.id) || bookIDs.contains($0.bookID)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            TextField("搜索单词、词组、笔记、词书", text: $query).textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused).padding(18)
            if query.isEmpty { QuietEmptyState(title: "找到你想复习的内容", detail: "一次搜索，覆盖本地词库、笔记和词书。", icon: "magnifyingglass") }
            else if matches.isEmpty { QuietEmptyState(title: "没有找到相关内容", detail: "试试英文单词、中文义或笔记中的关键词。", icon: "magnifyingglass") }
            else {
                List(matches) { word in
                    NavigationLink(value: WordDestination(id: word.id)) { WordRowView(word: word) }
                }.listStyle(.plain)
            }
        }.navigationTitle("全局搜索").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .navigationDestination(for: WordDestination.self) { WordDetailView(wordID: $0.id) }
            .onAppear { focused = true }
    }
}
