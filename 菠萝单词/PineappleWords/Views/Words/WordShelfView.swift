import SwiftUI
import PineappleCore

@MainActor
struct WordShelfView: View {
    @EnvironmentObject private var store: AppStore
    var words: [Vocabulary]
    var emptyMessage: String
    @State private var selected: UUID?
    @State private var search = ""
    private var filtered: [Vocabulary] {
        search.isEmpty ? words : words.filter { $0.details.searchableText.localizedStandardContains(search) }
    }
    var body: some View {
        GeometryReader { geometry in
            if words.isEmpty { QuietEmptyState(title: "这里暂时没有单词", detail: emptyMessage) }
            else {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        TextField("搜索当前词表", text: $search).textFieldStyle(.roundedBorder).padding(12)
                        List(filtered) { word in
                            if geometry.size.width >= 760 {
                                Button { selected = word.id } label: { WordRowView(word: word) }
                                    .buttonStyle(.plain)
                                    .listRowBackground(selected == word.id ? Palette.accent.opacity(0.1) : Color.clear)
                            } else {
                                NavigationLink(value: WordDestination(id: word.id)) { WordRowView(word: word) }
                            }
                        }.listStyle(.plain)
                        Text("\(filtered.count) 个词条").font(.caption).foregroundStyle(.secondary).padding(10)
                    }.frame(maxWidth: geometry.size.width >= 760 ? 320 : .infinity)
                    if geometry.size.width >= 760 {
                        Divider()
                        if let selected, filtered.contains(where: { $0.id == selected }) {
                            WordDetailView(wordID: selected).id(selected).frame(maxWidth: .infinity)
                        } else {
                            QuietEmptyState(title: "选一个词，慢慢学", detail: "左侧浏览词表，右侧阅读释义、例句和笔记。")
                        }
                    }
                }
            }
        }
    }
}
