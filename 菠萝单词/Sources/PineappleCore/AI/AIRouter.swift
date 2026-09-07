import Foundation

public enum AITask: String, Sendable {
    case chat, wordAnalysis, bookImport, hardQuestion, errorDiagnosis
    public var requiresDepth: Bool { [.bookImport, .hardQuestion, .errorDiagnosis].contains(self) }
}
public enum AIRouter {
    public static func resolve(_ selection: AIMode, task: AITask, question: String) -> AIMode {
        if task.requiresDepth { return .deep }
        if selection != .auto { return selection }
        let query = question.lowercased()
        let signals = ["为什么", "为何", "必须", "而不能", "深入", "复杂", "整课", "诊断", "频繁", "语法结构", "词汇结构", "have been", "had been", "compare", "why must", "区别与", "纠错"]
        return query.count > 180 || signals.contains(where: query.contains) ? .deep : .fast
    }
}

public struct AIAnswer: Codable, Equatable, Sendable {
    public var answer: String
    public var examples: [ExampleSentence]?
    public var caution: String?
    public init(answer: String, examples: [ExampleSentence]? = nil, caution: String? = nil) {
        self.answer = answer; self.examples = examples; self.caution = caution
    }
    public var displayText: String {
        var result = answer
        for example in examples ?? [] { result += "\n\n\(example.english)" + (example.chinese.map { "\n\($0)" } ?? "") }
        if let caution, !caution.isEmpty { result += "\n\n提示：\(caution)" }
        return result
    }
}
public struct AIQuestionDraft: Codable, Sendable {
    public var prompt: String
    public var correctAnswer: String
    public var explanation: String
    public var sourceQuote: String
    public init(prompt: String, correctAnswer: String, explanation: String, sourceQuote: String) {
        self.prompt = prompt; self.correctAnswer = correctAnswer; self.explanation = explanation; self.sourceQuote = sourceQuote
    }
    public func validated(for word: Vocabulary) throws -> StudyQuestion {
        let source = word.details
        let evidence = (source.examples ?? []).map(\.english) + (source.phrases ?? [])
            + (source.inflections ?? []) + (source.derivatives ?? []) + (source.synonyms ?? [])
            + [source.english_definition ?? "", source.coreMeaning]
        guard TextKey.normalize(correctAnswer) == TextKey.normalize(word.word), !prompt.isEmpty,
              prompt.contains("___"), prompt.count <= 2000, !sourceQuote.isEmpty,
              evidence.contains(sourceQuote), !QuestionFactory.containsWholeWord(prompt, word: word.word)
        else { throw AppError.invalidData("AI 练习改变了答案、泄露答案或缺少已有词条依据。请重试或使用本地题目。") }
        return StudyQuestion(wordID: word.id, kind: .aiContext, prompt: prompt, correctAnswer: word.word, explanation: explanation)
    }
}
