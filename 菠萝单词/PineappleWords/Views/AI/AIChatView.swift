import SwiftUI
import PineappleCore

@MainActor
struct AIChatView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AIChatViewModel()
    var wordID: UUID?
    var initialQuestion: String = ""
    @State private var loaded = false
    @State private var historyPresented = false
    private var entries: [ChatEntry] { store.snapshot.chats.filter { $0.threadID == model.threadID } }
    private var word: Vocabulary? { wordID.flatMap { store.snapshot.word($0) } }
    private var threads: [ChatEntry] {
        var seen = Set<UUID>()
        return store.snapshot.chats.reversed().filter { $0.wordID == wordID && seen.insert($0.threadID).inserted }
    }
    var body: some View {
        VStack(spacing: 0) {
            if let word {
                HStack { Text(word.word).font(.headline); Text(word.details.coreMeaning).foregroundStyle(.secondary); Spacer() }
                    .padding(16).background(Palette.card)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if entries.isEmpty {
                            Surface(word == nil ? "从一个问题开始" : "结合这个词，问得更具体") {
                                Text("发送时会提供当前词义、Lesson 和最近一道答题记录。对话保存在本地。")
                                    .foregroundStyle(.secondary).lineSpacing(5)
                                if word != nil {
                                    ForEach(["这个词怎么记？", "给我三个简单例句。", "为什么我刚才答错？", "分析我在这个词上的频繁错误。"], id: \.self) { text in
                                        Button(text) { model.input = text }
                                    }
                                }
                            }
                        }
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Text(entry.role == "user" ? "我" : "学习助手").font(.caption.bold())
                                    if entry.role == "assistant" { Text(entry.mode.title).font(.caption).foregroundStyle(.secondary) }
                                    Spacer(); Text(entry.date, style: .time).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(entry.content).lineSpacing(7).textSelection(.enabled)
                            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                                .background(entry.role == "user" ? Palette.accent.opacity(0.08) : Palette.card,
                                            in: RoundedRectangle(cornerRadius: 16)).id(entry.id)
                        }
                        if model.working { HStack { ProgressView(); Text("\(model.resolvedMode.title)模式正在回答…").foregroundStyle(.secondary); Spacer(); Button("取消") { model.cancel() } } }
                        if let error = model.errorMessage {
                            InlineNotice(text: error)
                            Button("重试上一个问题") { model.send(wordID: wordID, store: store, retry: true) }.disabled(model.working)
                        }
                    }.padding(22).frame(maxWidth: 860).frame(maxWidth: .infinity)
                }.onChange(of: entries.count) { _, _ in if let id = entries.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
            }
            VStack(spacing: 10) {
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("输入英语学习问题", text: $model.input, axis: .vertical).lineLimit(1...5)
                        .textFieldStyle(.roundedBorder).onChange(of: model.input) { _, _ in store.activity() }
                    Button { model.send(wordID: wordID, store: store) } label: { Label("发送", systemImage: "arrow.up") }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                        .disabled(model.working || model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("仅在发送时联网至 DeepSeek · AI 内容仅供学习参考").font(.caption2).foregroundStyle(.secondary)
            }.padding(18).background(Palette.card)
        }
        .background(Palette.background).navigationTitle(word == nil ? "AI 问答" : "问 AI · \(word?.word ?? "")")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu("对话") {
                    Button("新对话") { model.newConversation() }
                    Button("历史对话") { historyPresented = true }
                }
                if wordID != nil { Button("完成") { dismiss() } }
            }
        }
        .sheet(isPresented: $historyPresented) {
            NavigationStack {
                List(threads) { entry in
                    Button {
                        model.cancel(); model.threadID = entry.threadID; historyPresented = false
                    } label: {
                        VStack(alignment: .leading) {
                            Text(store.snapshot.chats.first { $0.threadID == entry.threadID && $0.role == "user" }?.content ?? "对话").lineLimit(2)
                            Text(entry.date, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.navigationTitle("历史对话")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { historyPresented = false } } }
            }
        }
        .onAppear {
            if !loaded { model.load(wordID: wordID, store: store); model.input = initialQuestion; loaded = true }
            store.activity()
        }
        .onDisappear { model.cancel(); store.leaveLearning() }
    }
}
