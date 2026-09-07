import Foundation

public struct Book: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var description: String
    public var cover: String
    public var createdDate: Date
    public var source: String
    public var importFingerprint: String?

    public init(id: UUID = UUID(), name: String, description: String = "", cover: String = "book.closed",
                createdDate: Date = Date(), source: String = "个人导入", importFingerprint: String? = nil) {
        self.id = id; self.name = name; self.description = description; self.cover = cover
        self.createdDate = createdDate; self.source = source; self.importFingerprint = importFingerprint
    }
}

public struct Chapter: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var bookID: UUID
    public var lessonNumber: Int
    public var lessonName: String
    public init(id: UUID = UUID(), bookID: UUID, lessonNumber: Int, lessonName: String) {
        self.id = id; self.bookID = bookID; self.lessonNumber = lessonNumber; self.lessonName = lessonName
    }
}

public struct ExampleSentence: Codable, Equatable, Sendable {
    public var english: String
    public var chinese: String?
    public init(english: String, chinese: String? = nil) { self.english = english; self.chinese = chinese }
}

/// Optional dictionary fields remain genuinely absent when the source supplies no information.
public struct LexicalDetails: Codable, Equatable, Sendable {
    public var word: String
    public var ipa: String?
    public var part_of_speech: [String]?
    public var meanings: [String]?
    public var english_definition: String?
    public var common_meanings: [String]?
    public var inflections: [String]?
    public var derivatives: [String]?
    public var roots: [String]?
    public var synonyms: [String]?
    public var antonyms: [String]?
    public var phrases: [String]?
    public var examples: [ExampleSentence]?

    public init(word: String, ipa: String? = nil, part_of_speech: [String]? = nil,
                meanings: [String]? = nil, english_definition: String? = nil,
                common_meanings: [String]? = nil, inflections: [String]? = nil,
                derivatives: [String]? = nil, roots: [String]? = nil,
                synonyms: [String]? = nil, antonyms: [String]? = nil,
                phrases: [String]? = nil, examples: [ExampleSentence]? = nil) {
        self.word = word; self.ipa = ipa; self.part_of_speech = part_of_speech
        self.meanings = meanings; self.english_definition = english_definition
        self.common_meanings = common_meanings; self.inflections = inflections
        self.derivatives = derivatives; self.roots = roots; self.synonyms = synonyms
        self.antonyms = antonyms; self.phrases = phrases; self.examples = examples
    }
    public var coreMeaning: String { meanings?.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "" }
    public var searchableText: String {
        ([word, ipa ?? "", coreMeaning, english_definition ?? ""] + (phrases ?? []) + (meanings ?? []))
            .joined(separator: " ")
    }
}

public struct Vocabulary: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var bookID: UUID
    public var chapterID: UUID
    public var details: LexicalDetails
    public var progress: WordProgress
    public var isFavorite: Bool
    public var isInMistakes: Bool
    /// nil follows the algorithm; false is a durable manual exclusion.
    public var confusingOverride: Bool?
    public var weakOverride: Bool?
    public var aiAnalysis: LexicalDetails?

    public init(id: UUID = UUID(), bookID: UUID, chapterID: UUID, details: LexicalDetails,
                progress: WordProgress = WordProgress(), isFavorite: Bool = false,
                isInMistakes: Bool = false, confusingOverride: Bool? = nil, weakOverride: Bool? = nil) {
        self.id = id; self.bookID = bookID; self.chapterID = chapterID; self.details = details
        self.progress = progress; self.isFavorite = isFavorite; self.isInMistakes = isInMistakes
        self.confusingOverride = confusingOverride; self.weakOverride = weakOverride
    }
    public var word: String { details.word }
    public func isConfusing(threshold: Int) -> Bool { confusingOverride ?? (progress.wrongCount >= threshold) }
    public func isWeak(at date: Date = Date()) -> Bool { weakOverride ?? ReviewEngine.isWeak(progress, at: date) }
}

public struct WordNote: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var wordID: UUID
    public var text: String
    public var updatedAt: Date
    public init(id: UUID = UUID(), wordID: UUID, text: String, updatedAt: Date = Date()) {
        self.id = id; self.wordID = wordID; self.text = text; self.updatedAt = updatedAt
    }
}

public enum TextKey {
    public static func normalize(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
