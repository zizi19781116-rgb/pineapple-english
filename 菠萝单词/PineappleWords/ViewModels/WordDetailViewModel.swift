import Foundation
import Combine
import PineappleCore

@MainActor
final class WordDetailViewModel: ObservableObject {
    @Published var generating = false
    @Published var errorMessage: String?
    @Published var collinsEntry: CollinsEntry?
    @Published var loadingCollins = false
    private var task: Task<Void, Never>?
    private var collinsTask: Task<Void, Never>?
    func analyse(_ word: Vocabulary, store: AppStore) {
        guard !generating else { return }
        generating = true; errorMessage = nil
        let settings = store.snapshot.settings, epoch = store.epoch
        task = Task {
            defer { generating = false }
            do {
                guard let key = try KeychainService.read(), !key.isEmpty else { throw AppError.ai("请先在设置中保存 DeepSeek API Key。") }
                let result = try await store.ai.structured(LexicalDetails.self, task: .wordAnalysis, question: word.word,
                                                           messages: AIPrompts.analysis(word), settings: settings, apiKey: key) {
                    guard TextKey.normalize($0.word) == TextKey.normalize(word.word), !($0.meanings ?? []).isEmpty else {
                        throw AppError.invalidData("单词不一致或没有释义。")
                    }
                }
                try Task.checkCancellation()
                guard epoch == store.epoch else { return }
                _ = store.editWord(word.id) { $0.aiAnalysis = result }; store.activity()
            } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
        }
    }
    func lookupCollins(_ word: String) {
        guard let provider = CollinsRegistry.provider, !loadingCollins else { return }
        loadingCollins = true
        collinsTask = Task {
            defer { loadingCollins = false }
            do { collinsEntry = try await provider.lookup(word) }
            catch is CancellationError {} catch { errorMessage = error.localizedDescription }
        }
    }
    func cancel() { task?.cancel(); collinsTask?.cancel() }
}
