import SwiftUI
import PineappleCore

@MainActor
struct WordDetailView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var model = WordDetailViewModel()
    let wordID: UUID
    @State private var showAI = false
    @State private var editing = false
    @State private var session: SessionRequest?
    @State private var note = ""
    @State private var noteReady = false
    @State private var noteTask: Task<Void, Never>?
    @State private var noteStatus = ""
    @State private var entryEpoch: UUID?
    @State private var showAnswerHistory = false
    private var word: Vocabulary? { store.snapshot.word(wordID) }
    private func enabled(_ module: CardModule) -> Bool { store.snapshot.settings.cardModules.contains(module) }
    var body: some View {
        Group {
            if let word {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        wordHeader(word)
                        dictionaryModules(word.details)
                        if enabled(.ai) { aiModule(word) }
                        if enabled(.notes) { noteModule }
                        if enabled(.collins), store.snapshot.settings.collinsEnabled, CollinsRegistry.isConfigured { collinsModule(word) }
                        progressModule(word)
                        if let error = model.errorMessage { InlineNotice(text: error) }
                    }.padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity)
                }.simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in store.activity() })
            } else { QuietEmptyState(title: "找不到这个单词", detail: "词条可能已在数据迁入后发生变化。") }
        }
        .background(Palette.background)
        .sheet(isPresented: $showAI) { NavigationStack { AIChatView(wordID: wordID) }.environmentObject(store) }
        .sheet(isPresented: $editing) { NavigationStack { WordEditorView(wordID: wordID) }.environmentObject(store) }
        .sheet(item: $session) { request in NavigationStack { StudySessionView(scope: request.scope) }.environmentObject(store) }
        .onAppear {
            entryEpoch = store.epoch
            note = store.unsavedNotes[wordID] ?? store.snapshot.notes.first { $0.wordID == wordID }?.text ?? ""
            noteReady = true; store.activity()
        }
        .onDisappear {
            model.cancel(); noteTask?.cancel()
            saveNoteIfNeeded(); store.leaveLearning()
        }
    }
    private func wordHeader(_ word: Vocabulary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(word.word).font(.system(.largeTitle, design: .rounded, weight: .semibold)).textSelection(.enabled)
                    if enabled(.ipa), let ipa = word.details.ipa { Text(ipa).font(.title3).foregroundStyle(.secondary) }
                }
                Spacer()
                Button { store.play(word.word) } label: { Image(systemName: "speaker.wave.2.fill").font(.title2).padding(10) }
                    .keyboardShortcut("r", modifiers: .command).accessibilityLabel("播放单词英音")
                Button { store.editWord(word.id) { $0.isFavorite.toggle() } } label: {
                    Image(systemName: word.isFavorite ? "bookmark.fill" : "bookmark").font(.title2).padding(10)
                }.accessibilityLabel(word.isFavorite ? "取消收藏" : "收藏单词")
            }
            let book = store.snapshot.books.first { $0.id == word.bookID }
            let chapter = store.snapshot.chapters.first { $0.id == word.chapterID }
            Text([book?.name, chapter?.lessonName].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack { wordActions(word) }
                VStack(alignment: .leading) { wordActions(word) }
            }
        }
    }
    @ViewBuilder private func wordActions(_ word: Vocabulary) -> some View {
        Button("练习这个词") { session = SessionRequest(scope: .words([word.id])) }.buttonStyle(.borderedProminent)
        Button("问 AI") { store.activity(); showAI = true }.buttonStyle(.bordered)
        Menu {
            Button("编辑词条资料") { editing = true }
            Button(word.isInMistakes ? "移出错题本" : "加入错题本") { store.editWord(word.id) { $0.isInMistakes.toggle() } }
            Button("标记已掌握") { store.markMastered(word.id) }
            Button(word.isConfusing(threshold: store.snapshot.settings.confusingWrongThreshold) ? "移出易错词" : "加入易错词") {
                store.editWord(word.id) { $0.confusingOverride = !word.isConfusing(threshold: store.snapshot.settings.confusingWrongThreshold) }
            }
            Button(word.isWeak() ? "移出薄弱词" : "加入薄弱词") { store.editWord(word.id) { $0.weakOverride = !word.isWeak() } }
            Button("易错与薄弱恢复自动判断") { store.editWord(word.id) { $0.confusingOverride = nil; $0.weakOverride = nil } }
        } label: { Label("更多", systemImage: "ellipsis") }.buttonStyle(.bordered)
    }
    @ViewBuilder private func dictionaryModules(_ details: LexicalDetails) -> some View {
        if enabled(.chinese), !(details.meanings ?? []).isEmpty {
            Surface("中文释义") {
                FlowText(items: details.meanings ?? [])
                if !(details.common_meanings ?? []).isEmpty { FlowText(items: details.common_meanings ?? []).foregroundStyle(.secondary) }
            }
        }
        if enabled(.partOfSpeech), !(details.part_of_speech ?? []).isEmpty { Surface("词性") { FlowText(items: details.part_of_speech ?? []) } }
        if enabled(.english), let value = details.english_definition, !value.isEmpty { Surface("英文释义") { Text(value).lineSpacing(6).textSelection(.enabled) } }
        if enabled(.examples), let examples = details.examples, !examples.isEmpty {
            Surface("例句") {
                ForEach(Array(examples.enumerated()), id: \.offset) { _, example in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(example.english).lineSpacing(6).textSelection(.enabled)
                            if let chinese = example.chinese { Text(chinese).font(.subheadline).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 4)
                        Button { store.play(example.english) } label: { Image(systemName: "speaker.wave.2").padding(8) }.accessibilityLabel("播放例句英音")
                    }
                }
            }
        }
        listModule(.phrases, values: details.phrases); listModule(.inflections, values: details.inflections)
        listModule(.derivatives, values: details.derivatives); listModule(.roots, values: details.roots)
        listModule(.synonyms, values: details.synonyms); listModule(.antonyms, values: details.antonyms)
        if details.coreMeaning.isEmpty { InlineNotice(text: "这条资料没有中文释义，可以通过“更多 → 编辑词条资料”补全。") }
    }
    @ViewBuilder private func listModule(_ module: CardModule, values: [String]?) -> some View {
        if enabled(module), let values, !values.isEmpty { Surface(module.title) { FlowText(items: values) } }
    }
    private func aiModule(_ word: Vocabulary) -> some View {
        Surface("AI 解析") {
            if let analysis = word.aiAnalysis {
                Text("AI 辅助内容，请结合原始资料核对。").font(.caption).foregroundStyle(.secondary)
                FlowText(items: analysis.meanings ?? [])
                if let english = analysis.english_definition { Text(english).lineSpacing(5) }
                ForEach(Array((analysis.examples ?? []).enumerated()), id: \.offset) { _, example in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(example.english); if let chinese = example.chinese { Text(chinese).foregroundStyle(.secondary) }
                    }
                }
                if !(analysis.roots ?? []).isEmpty { Text("词根词缀：" + (analysis.roots ?? []).joined(separator: "；")) }
                if !(analysis.derivatives ?? []).isEmpty { Text("派生词：" + (analysis.derivatives ?? []).joined(separator: "；")) }
                if !(analysis.synonyms ?? []).isEmpty { Text("近义词：" + (analysis.synonyms ?? []).joined(separator: "；")) }
                if !(analysis.antonyms ?? []).isEmpty { Text("反义词：" + (analysis.antonyms ?? []).joined(separator: "；")) }
            } else { Text("解释、例句与记忆线索，按需生成并保存在本地。").foregroundStyle(.secondary) }
            if model.generating { HStack { ProgressView(); Text("正在生成…"); Spacer(); Button("取消") { model.cancel() } } }
            else { Button(word.aiAnalysis == nil ? "生成解析" : "重新生成解析") { store.activity(); model.analyse(word, store: store) }.buttonStyle(.bordered) }
            Text("仅将当前词条资料发送给 DeepSeek。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var noteModule: some View {
        Surface("我的笔记") {
            TextEditor(text: $note).frame(minHeight: 130).scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) { if note.isEmpty { Text("记下容易混淆的地方，或工作中的用法。").foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false) } }
                .onChange(of: note) { _, _ in
                    guard noteReady else { return }
                    store.unsavedNotes[wordID] = note
                    store.activity(); noteStatus = "正在保存…"; noteTask?.cancel()
                    noteTask = Task {
                        do { try await Task.sleep(nanoseconds: 600_000_000); try Task.checkCancellation(); saveNoteIfNeeded() }
                        catch {}
                    }
                }
            HStack { Text(noteStatus).font(.caption).foregroundStyle(.secondary); Spacer(); Button("保存笔记") { saveNoteIfNeeded() } }
        }
    }
    private func saveNoteIfNeeded() {
        guard noteReady, entryEpoch == store.epoch else { return }
        let saved = store.snapshot.notes.first { $0.wordID == wordID }?.text ?? ""
        guard note.trimmingCharacters(in: .whitespacesAndNewlines) != saved else {
            noteStatus = "已保存到本地"; store.unsavedNotes[wordID] = nil; return
        }
        noteStatus = store.saveNote(wordID: wordID, text: note) ? "已保存到本地" : "保存失败，请保留当前页面并重试"
        if noteStatus == "已保存到本地" { store.unsavedNotes[wordID] = nil }
    }
    private func collinsModule(_ word: Vocabulary) -> some View {
        Surface("Collins") {
            if let entry = model.collinsEntry {
                FlowText(items: entry.definitions)
                Text(entry.attribution).font(.caption).foregroundStyle(.secondary)
            } else { Button("查询授权词典") { model.lookupCollins(word.word); store.activity() }.disabled(model.loadingCollins) }
        }
    }
    private func progressModule(_ word: Vocabulary) -> some View {
        Surface("学习记录") {
            Text(word.progress.masteryLevel.title).font(.headline)
            Text("共回答 \(word.progress.totalAnswers) 次 · 正确 \(word.progress.correctCount) · 错误 \(word.progress.wrongCount)")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("连续正确 \(word.progress.streakCorrect) 次 · 连续错误 \(word.progress.streakWrong) 次")
                .font(.subheadline).foregroundStyle(.secondary)
            if let date = word.progress.nextReviewDate { LabeledContent("下次复习", value: date.formatted(date: .abbreviated, time: .shortened)) }
            if let date = word.progress.lastWrongDate { LabeledContent("最近错误", value: date.formatted(date: .abbreviated, time: .shortened)) }
            DisclosureGroup("最近答题记录", isExpanded: $showAnswerHistory) {
                let events = Array(store.snapshot.answers.filter { $0.wordID == word.id }.suffix(10).reversed())
                if events.isEmpty { Text("完成一次练习后，这里会保留题目和你的答案。").foregroundStyle(.secondary) }
                ForEach(events) { event in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Label(event.isCorrect ? "正确" : "错误", systemImage: event.isCorrect ? "checkmark.circle" : "xmark.circle")
                                .foregroundStyle(event.isCorrect ? Color.green : Color.orange)
                            Spacer(); Text(event.date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(event.question.prompt).lineLimit(4)
                        Text("你的答案：\(event.userAnswer)").font(.subheadline)
                        Text("正确答案：\(event.question.correctAnswer)").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
            }.onChange(of: showAnswerHistory) { _, _ in store.activity() }
        }
    }
}
