import SwiftUI
import PineappleCore

@MainActor
struct BooksView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedBook: UUID?
    @State private var selectedChapter: UUID?
    @State private var importer = false
    @State private var session: SessionRequest?
    var body: some View {
        Group {
            if let id = selectedBook, let book = store.snapshot.books.first(where: { $0.id == id }) {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button { selectedBook = nil; selectedChapter = nil } label: { Label("所有词书", systemImage: "chevron.left") }
                            Spacer()
                            if store.snapshot.settings.mainBookID == book.id {
                                Label("主词书", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                Button("设为主词书") { store.updateSettings { $0.mainBookID = book.id } }.buttonStyle(.bordered)
                            }
                        }
                        Text(book.name).font(.title2.bold())
                        if !book.description.isEmpty { Text(book.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
                        HStack {
                            Picker("Lesson", selection: $selectedChapter) {
                                Text("全部 Lesson").tag(nil as UUID?)
                                ForEach(store.snapshot.chapters(in: book.id)) { chapter in
                                    Text(chapter.lessonName).tag(Optional(chapter.id))
                                }
                            }.pickerStyle(.menu)
                            Spacer()
                            Button("练习\(selectedChapter == nil ? "整本词书" : "本课")") {
                                session = SessionRequest(scope: .words(filteredWords(book.id).map(\.id)))
                            }.buttonStyle(.borderedProminent)
                        }
                    }.padding(20)
                    Divider()
                    WordShelfView(words: filteredWords(book.id), emptyMessage: "这课还没有单词。")
                }
            } else if store.snapshot.books.isEmpty {
                VStack(spacing: 16) {
                    QuietEmptyState(title: "你的词书，从这里开始", detail: "支持 TXT、CSV、JSON、PDF 和粘贴文本。先检查预览，再加入本地词库。")
                    Button("导入第一本词书") { importer = true }.buttonStyle(.borderedProminent).controlSize(.large)
                }.padding(.bottom, 80)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 18)], spacing: 18) {
                        ForEach(store.snapshot.books) { book in
                            Button { selectedBook = book.id; selectedChapter = nil } label: {
                                Surface {
                                    HStack { Image(systemName: book.cover).font(.largeTitle).foregroundStyle(Palette.accent)
                                        Spacer(); if store.snapshot.settings.mainBookID == book.id { Text("主词书").font(.caption).foregroundStyle(.secondary) } }
                                    Text(book.name).font(.title2.bold()).multilineTextAlignment(.leading)
                                    Text("\(store.snapshot.chapters(in: book.id).count) 课 · \(store.snapshot.words(in: book.id).count) 词")
                                        .foregroundStyle(.secondary)
                                    let words = store.snapshot.words(in: book.id)
                                    let learned = words.filter { $0.progress.totalAnswers > 0 }.count
                                    ProgressView(value: Double(learned), total: Double(max(1, words.count)))
                                    Text("已学 \(learned) · \(book.source)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding(24)
                }
            }
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { importer = true } label: { Label("导入词书", systemImage: "plus") } } }
        .sheet(isPresented: $importer) { NavigationStack { BookImportView() }.environmentObject(store) }
        .sheet(item: $session) { request in NavigationStack { StudySessionView(scope: request.scope) }.environmentObject(store) }
    }
    private func filteredWords(_ bookID: UUID) -> [Vocabulary] {
        store.snapshot.words.filter { $0.bookID == bookID && (selectedChapter == nil || $0.chapterID == selectedChapter) }
    }
}
