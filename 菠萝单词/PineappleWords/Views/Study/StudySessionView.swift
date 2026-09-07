import SwiftUI
import PineappleCore

@MainActor
struct StudySessionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = StudySessionViewModel()
    @State private var started = false
    @State private var preferred: QuestionKind = .choice
    @State private var askAI = false
    @FocusState private var inputFocused: Bool
    let scope: StudyScope
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !started { setup }
                else if model.finished { finished }
                else if let question = model.question { questionBody(question) }
                else {
                    QuietEmptyState(title: "本轮没有可练习的单词", detail: model.errorMessage ?? "可能已完成今日目标、尚无到期复习，或词条缺少释义。可到词书中选择单词练习。")
                    if !model.queue.isEmpty { Button("跳过这个词") { model.skipUnavailable(store: store) } }
                }
                if let error = model.errorMessage, model.question != nil { InlineNotice(text: error) }
            }.padding(24).frame(maxWidth: 820).frame(maxWidth: .infinity)
        }
        .background(Palette.background).navigationTitle(scope.title).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("结束") { dismiss() } } }
        .interactiveDismissDisabled(model.generating)
        .onDisappear { model.cancel(); store.leaveLearning() }
        .onChange(of: model.question?.id) { _, _ in inputFocused = true }
        .sheet(isPresented: $askAI) {
            NavigationStack { AIChatView(wordID: model.question?.wordID, initialQuestion: "为什么我刚才这样回答？请结合这道题解释。") }
                .environmentObject(store)
        }
    }
    private var setup: some View {
        Surface("选择练习方式") {
            Picker("练习方式", selection: $preferred) {
                Text("四选一").tag(QuestionKind.choice)
                Text("拼写").tag(QuestionKind.spelling)
                if store.snapshot.settings.hardMode { Text("听写").tag(QuestionKind.listening) }
            }.pickerStyle(.segmented)
            Toggle("困难模式", isOn: Binding(get: { store.snapshot.settings.hardMode }, set: { value in store.updateSettings { $0.hardMode = value } }))
            Text(store.snapshot.settings.hardMode ? "减少提示，优先使用例句填空、英文释义或英音听写。练习中可按需生成 AI 深度语境题。" : "根据词书资料练习。拼写题提供词性、首字母和已有例句辅助。")
                .foregroundStyle(.secondary).lineSpacing(5)
            Button("开始练习") {
                started = true; model.start(store: store, scope: scope, preferred: preferred)
            }.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }
    private func questionBody(_ question: StudyQuestion) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("\(min(model.index + 1, model.queue.count)) / \(model.queue.count)").monospacedDigit()
                Spacer(); Text(question.kind.title)
            }.font(.subheadline).foregroundStyle(.secondary)
            ProgressView(value: Double(model.index), total: Double(max(1, model.queue.count)))
            Surface {
                if question.kind == .listening {
                    Image(systemName: "waveform").font(.system(size: 42)).foregroundStyle(Palette.accent)
                }
                Text(question.prompt).font(.system(question.kind == .choice ? .largeTitle : .title2, design: .rounded, weight: .medium))
                    .lineSpacing(8).textSelection(.enabled).accessibilityIdentifier("questionPrompt")
                if let hint = question.hint, !hint.isEmpty { Text(hint).font(.title3).foregroundStyle(.secondary).lineSpacing(8) }
                if question.kind == .choice || question.kind == .listening {
                    Button { playQuestion(question) } label: { Label("播放英音", systemImage: "speaker.wave.2.fill") }
                        .keyboardShortcut("r", modifiers: .command).buttonStyle(.bordered)
                }
            }
            if question.kind == .choice {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    Button { model.submit(store: store, answer: option) } label: {
                        HStack(spacing: 16) {
                            Text(String(UnicodeScalar(65 + index) ?? "A")).font(.headline).frame(width: 26)
                            Text(option).font(.title3); Spacer()
                            if model.feedback != nil && question.accepts(option) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).disabled(model.feedback != nil || model.generating)
                }
            } else {
                TextField("输入英文答案", text: $model.input)
                    .font(.title2).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().keyboardType(.asciiCapable).submitLabel(.done)
                    .focused($inputFocused).disabled(model.feedback != nil || model.generating)
                    .accessibilityIdentifier("spellingInput")
                    .onChange(of: model.input) { _, _ in store.activity() }
                    .onSubmit { if model.feedback == nil { model.submit(store: store) } else { model.advance(store: store) } }
                if model.feedback == nil {
                    Button("提交答案") { model.submit(store: store) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(TextKey.normalize(model.input).isEmpty || model.generating)
                        .accessibilityIdentifier("submitAnswer")
                }
            }
            if let feedback = model.feedback { feedbackBody(feedback) }
            else if store.snapshot.settings.hardMode {
                if model.generating { HStack { ProgressView(); Text("正在生成深度语境题…"); Spacer(); Button("取消") { model.cancel() } } }
                else {
                    Button("生成 AI 深度语境题") { model.generateHardQuestion(store: store) }.buttonStyle(.bordered)
                    Text("将当前词条资料发送给 DeepSeek，答案须通过本地一致性检查。").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func playQuestion(_ question: StudyQuestion) {
        if let word = store.snapshot.word(question.wordID) { store.play(word.word) }
    }
    private func feedbackBody(_ event: AnswerEvent) -> some View {
        Surface {
            Label(event.isCorrect ? "回答正确" : "再记一次", systemImage: event.isCorrect ? "checkmark.circle.fill" : "arrow.counterclockwise.circle")
                .font(.headline).foregroundStyle(event.isCorrect ? Color.green : Color.orange)
            Text("正确答案：\(event.question.correctAnswer)").font(.title3).textSelection(.enabled)
            if !event.isCorrect { Text("你的答案：\(event.userAnswer)").foregroundStyle(.secondary) }
            if let explanation = event.question.explanation { Text(explanation).lineSpacing(5) }
            if let word = store.snapshot.word(event.wordID) {
                Text("\(word.word) · \(word.details.coreMeaning)").foregroundStyle(.secondary)
                Button { store.play(word.word) } label: { Label("再听一次英音", systemImage: "speaker.wave.2") }
                    .keyboardShortcut("r", modifiers: .command)
            }
            HStack {
                Button("下一题") { model.advance(store: store) }.buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                Button("问 AI") { askAI = true }.buttonStyle(.bordered)
            }
        }
    }
    private var finished: some View {
        Surface("这一轮，已认真完成。") {
            Text("完成 \(model.completed) 次练习，答对 \(model.correct) 次。").font(.title2)
            Text("答题记录和复习计划已保存在本地。错题会按你设置的连续正确次数移出。")
                .foregroundStyle(.secondary).lineSpacing(5)
            Button("完成") { dismiss() }.buttonStyle(.borderedProminent)
        }
    }
}
