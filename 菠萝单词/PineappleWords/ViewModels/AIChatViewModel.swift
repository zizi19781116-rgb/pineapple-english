import Foundation
import Combine
import PineappleCore

@MainActor
final class AIChatViewModel: ObservableObject {
    @Published var threadID = UUID()
    @Published var input = ""
    @Published var working = false
    @Published var errorMessage: String?
    @Published var resolvedMode: AIMode = .auto
    private var task: Task<Void, Never>?
    private var pendingQuestion: String?

    func load(wordID: UUID?, store: AppStore) {
        if let entry = store.snapshot.chats.last(where: { $0.wordID == wordID }) { threadID = entry.threadID }
    }
    func newConversation() { cancel(); threadID = UUID(); errorMessage = nil; pendingQuestion = nil }
    func send(wordID: UUID?, store: AppStore, retry: Bool = false) {
        guard !working else { return }
        let question = (retry ? pendingQuestion ?? input : input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        guard question.count <= 12000 else { errorMessage = "问题过长，请控制在 12000 字以内。"; return }
        let snapshot = store.snapshot, epoch = store.epoch, thread = threadID
        let word = wordID.flatMap { snapshot.word($0) }
        let history = snapshot.chats.filter { $0.threadID == thread }
        let reuseUserMessage = retry && history.last?.role == "user" && history.last?.content == question
        let taskType: AITask = question.contains("错误分析") || question.contains("频繁错误") || question.contains("诊断") ? .errorDiagnosis : .chat
        resolvedMode = AIRouter.resolve(snapshot.settings.aiMode, task: taskType, question: question)
        let mode = resolvedMode
        let messages = AIPrompts.chat(question: question, word: word, snapshot: snapshot,
                                      history: reuseUserMessage ? Array(history.dropLast()) : history)
        working = true; errorMessage = nil; pendingQuestion = question
        task = Task {
            defer { working = false }
            do {
                guard let key = try KeychainService.read(), !key.isEmpty else { throw AppError.ai("请先在设置中保存 DeepSeek API Key。") }
                if !reuseUserMessage {
                    guard store.appendChat(ChatEntry(threadID: thread, wordID: wordID, role: "user", content: question, mode: mode), expectedEpoch: epoch)
                    else { throw AppError.storage("问题还未保存，请先重试。") }
                    input = ""
                }
                store.activity()
                let result = try await store.ai.structured(AIAnswer.self, task: taskType, question: question,
                                                           messages: messages, settings: snapshot.settings, apiKey: key) {
                    guard !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.invalidData("AI 答案为空。") }
                }
                try Task.checkCancellation()
                guard epoch == store.epoch, thread == threadID else { return }
                guard store.appendChat(ChatEntry(threadID: thread, wordID: wordID, role: "assistant", content: result.displayText, mode: mode), expectedEpoch: epoch)
                else { throw AppError.storage("AI 回答未保存，请重试。") }
                pendingQuestion = nil; store.activity()
            } catch is CancellationError { if thread == threadID { errorMessage = "已取消请求，可以继续本地学习。" } }
            catch { if thread == threadID { errorMessage = error.localizedDescription } }
        }
    }
    func cancel() { task?.cancel() }
}
