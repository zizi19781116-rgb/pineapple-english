import Foundation

public enum MasteryLevel: Int, Codable, CaseIterable, Sendable {
    case unfamiliar, recognised, familiar, mastered, retained
    public var title: String { ["陌生", "认识", "熟悉", "掌握", "长期掌握"][rawValue] }
}

public struct WordProgress: Codable, Equatable, Sendable {
    public var masteryLevel: MasteryLevel = .unfamiliar
    public var nextReviewDate: Date?
    public var lastReviewDate: Date?
    public var lastAnswerDate: Date?
    public var lastWrongDate: Date?
    public var firstLearnedDate: Date?
    public var correctCount: Int = 0
    public var wrongCount: Int = 0
    public var streakCorrect: Int = 0
    public var streakWrong: Int = 0
    public var intervalSeconds: TimeInterval = 0
    public var ease: Double = 2.1
    public var recentOutcomes: [Bool] = []
    public var totalAnswers: Int { correctCount + wrongCount }
    public var accuracy: Double { totalAnswers == 0 ? 0 : Double(correctCount) / Double(totalAnswers) }
    public init() {}
}

public enum QuestionKind: String, Codable, CaseIterable, Sendable {
    case choice, spelling, definition, listening, cloze, aiContext
    public var title: String {
        switch self {
        case .choice: return "四选一"
        case .spelling: return "中文拼写"
        case .definition: return "英文释义拼写"
        case .listening: return "英音听写"
        case .cloze: return "例句填空"
        case .aiContext: return "语境练习"
        }
    }
}

public struct StudyQuestion: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var wordID: UUID
    public var kind: QuestionKind
    public var prompt: String
    public var hint: String?
    public var options: [String]
    public var correctAnswer: String
    public var explanation: String?
    public init(id: UUID = UUID(), wordID: UUID, kind: QuestionKind, prompt: String,
                hint: String? = nil, options: [String] = [], correctAnswer: String, explanation: String? = nil) {
        self.id = id; self.wordID = wordID; self.kind = kind; self.prompt = prompt; self.hint = hint
        self.options = options; self.correctAnswer = correctAnswer; self.explanation = explanation
    }
    public func accepts(_ answer: String) -> Bool { TextKey.normalize(answer) == TextKey.normalize(correctAnswer) }
}

public struct AnswerEvent: Codable, Identifiable, Equatable, Sendable {
    /// The question ID makes an accidental double-submit idempotent.
    public var id: UUID
    public var wordID: UUID
    public var date: Date
    public var question: StudyQuestion
    public var userAnswer: String
    public var isCorrect: Bool
    public var isFirstLearning: Bool
    public init(question: StudyQuestion, answer: String, date: Date = Date(), isFirstLearning: Bool) {
        id = question.id; wordID = question.wordID; self.date = date; self.question = question
        userAnswer = answer; isCorrect = question.accepts(answer); self.isFirstLearning = isFirstLearning
    }
}

public struct StudySlice: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    public init(id: UUID = UUID(), start: Date, end: Date) { self.id = id; self.start = start; self.end = end }
}

public struct ChatEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var threadID: UUID
    public var wordID: UUID?
    public var role: String
    public var content: String
    public var date: Date
    public var mode: AIMode
    public init(id: UUID = UUID(), threadID: UUID, wordID: UUID? = nil, role: String,
                content: String, date: Date = Date(), mode: AIMode) {
        self.id = id; self.threadID = threadID; self.wordID = wordID; self.role = role
        self.content = content; self.date = date; self.mode = mode
    }
}
