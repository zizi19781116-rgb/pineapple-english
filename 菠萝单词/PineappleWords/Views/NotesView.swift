import SwiftUI
import PineappleCore

@MainActor
struct NotesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    @State private var byDate = true
    private var notes: [WordNote] {
        let filtered = store.snapshot.notes.filter { note in
            search.isEmpty || note.text.localizedStandardContains(search)
                || (store.snapshot.word(note.wordID)?.word.localizedStandardContains(search) ?? false)
        }
        return filtered.sorted { first, second in
            byDate ? first.updatedAt > second.updatedAt : (store.snapshot.word(first.wordID)?.word ?? "") < (store.snapshot.word(second.wordID)?.word ?? "")
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            Picker("排序", selection: $byDate) { Text("按日期").tag(true); Text("按单词").tag(false) }
                .pickerStyle(.segmented).padding(16)
            if store.snapshot.notes.isEmpty { QuietEmptyState(title: "把理解留在词旁", detail: "在单词详情中写下笔记，这里会按单词或日期整理。", icon: "note.text") }
            else {
                List(notes) { note in
                    NavigationLink(value: WordDestination(id: note.wordID)) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(store.snapshot.word(note.wordID)?.word ?? "单词").font(.title3.bold())
                            Text(note.text).lineLimit(4).lineSpacing(4)
                            Text(note.updatedAt, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                }.listStyle(.plain)
            }
        }.searchable(text: $search, prompt: "搜索单词与笔记")
    }
}
