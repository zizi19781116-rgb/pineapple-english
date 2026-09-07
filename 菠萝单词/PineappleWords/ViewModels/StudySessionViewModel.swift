import Foundation
import Combine
import PineappleCore

@MainActor
final class StudySessionViewModel: ObservableObject {
    @Published private(set) var queue: [UUID] = []
    @Published private(set) var index = 0
    @Published private(set) var question: StudyQuestion?
    @Published private(set) var feedback: AnswerEvent?
    @Published private(set) var completed = 0
    @Published private(set) var correct = 0
    @Published var input = ""
    @Published var errorMessage: String?
    @Published var generating = false
    private var retryIDs: Set<UUID> = []
    private var task: Task<Void, Never>?
    private var preferred: QuestionKind = .choice
    private var epoch = UUID()

    var finished: Bool { !queue.isEmpty && index >= queue.count }
    func start(store: AppStore, scope: StudyScope, preferred: QuestionKind) {
        self.preferred = preferred; epoch = store.epoch
        let data = store.snapshot
        var words: [Vocabulary]
        var newWordLimit: Int?
        switch scope {
        case .newWords:
            let bookID = data.settings.mainBookID
            let chapters = data.chapters.filter { $0.bookID == bookID }.sorted { $0.lessonNumber < $1.lessonNumber }
            words = chapters.flatMap { chapter in data.words.filter { $0.chapterID == chapter.id && $0.progress.totalAnswers == 0 } }
            let today = StatisticsService.calculate(data, period: .day).newWords
            newWordLimit = max(0, data.settings.dailyNewGoal - today)
        case .due: words = data.dueWords()
        case .mistakes: words = data.words.filter(\.isInMistakes)
        case .confusing: words = data.words.filter { $0.isConfusing(threshold: data.settings.confusingWrongThreshold) }
        case .weak: words = data.words.filter { $0.isWeak() }
        case .book(let id): words = data.chapters(in: id).flatMap { chapter in data.words.filter { $0.chapterID == chapter.id } }
        case .words(let ids): words = ids.compactMap { data.word($0) }
        }
        words = words.filter { data.settings.hardMode || !$0.details.coreMeaning.isEmpty }
        if let newWordLimit { words = Array(words.prefix(newWordLimit)) }
        queue = words.map(\.id); index = 0; completed = 0; correct = 0; retryIDs = []
        nextQuestion(store: store)
    }
    private func nextQuestion(store: AppStore) {
        feedback = nil; input = ""; errorMessage = nil; question = nil
        guard index < queue.count, let word = store.snapshot.word(queue[index]), epoch == store.epoch else { return }
        do {
            question = try QuestionFactory.make(word: word, pool: store.snapshot.words,
                                                preferred: preferred, hard: store.snapshot.settings.hardMode,
                                                listeningAvailable: store.speech.isAvailable)
            store.activity()
        } catch { errorMessage = error.localizedDescription }
    }
    func submit(store: AppStore, answer: String? = nil) {
        guard feedback == nil, !generating, let question, epoch == store.epoch else { return }
        let value = answer ?? input
        guard !TextKey.normalize(value).isEmpty else { return }
        guard let event = store.submit(question, answer: value) else { return }
        feedback = event; completed += 1
        if event.isCorrect { correct += 1 }
        else if !retryIDs.contains(question.wordID) { queue.append(question.wordID); retryIDs.insert(question.wordID) }
    }
    func advance(store: AppStore) {
        guard feedback != nil else { return }
        index += 1; nextQuestion(store: store)
        if finished { store.leaveLearning() }
    }
    func skipUnavailable(store: AppStore) { index += 1; nextQuestion(store: store) }
    func generateHardQuestion(store: AppStore) {
        guard let original = question, let word = store.snapshot.word(original.wordID), !generating, feedback == nil else { return }
        generating = true; errorMessage = nil
        let settings = store.snapshot.settings, requestEpoch = store.epoch
        task = Task {
            defer { generating = false }
            do {
                guard let key = try KeychainService.read(), !key.isEmpty else { throw AppError.ai("请先在设置中保存 DeepSeek API Key。") }
                let draft = try await store.ai.structured(AIQuestionDraft.self, task: .hardQuestion, question: "困难模式题目",
                                                          messages: AIPrompts.hardQuestion(word), settings: settings, apiKey: key) {
                    _ = try $0.validated(for: word)
                }
                try Task.checkCancellation()
                guard store.epoch == requestEpoch, question?.id == original.id, feedback == nil else { return }
                question = try draft.validated(for: word); input = ""; store.activity()
            } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
        }
    }
    func cancel() { task?.cancel(); generating = false }
}
