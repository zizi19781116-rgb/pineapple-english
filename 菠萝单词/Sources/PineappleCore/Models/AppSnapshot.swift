import Foundation

/// Wire format is independent of SwiftData's physical SQLite schema.
public struct AppSnapshot: Codable, Equatable, Sendable {
    public var databaseVersion: Int = 1
    public var books: [Book] = []
    public var chapters: [Chapter] = []
    public var words: [Vocabulary] = []
    public var answers: [AnswerEvent] = []
    public var studySlices: [StudySlice] = []
    public var notes: [WordNote] = []
    public var chats: [ChatEntry] = []
    public var settings: UserSettings = UserSettings()
    public init() {}
    public var canonicalized: AppSnapshot {
        var copy = self
        copy.books.sort { $0.id.uuidString < $1.id.uuidString }
        copy.chapters.sort { $0.id.uuidString < $1.id.uuidString }
        copy.words.sort { $0.id.uuidString < $1.id.uuidString }
        copy.answers.sort { $0.id.uuidString < $1.id.uuidString }
        copy.studySlices.sort { $0.id.uuidString < $1.id.uuidString }
        copy.notes.sort { $0.id.uuidString < $1.id.uuidString }
        copy.chats.sort { $0.id.uuidString < $1.id.uuidString }
        return copy
    }
    public func word(_ id: UUID) -> Vocabulary? { words.first { $0.id == id } }
    public func chapters(in book: UUID) -> [Chapter] {
        chapters.filter { $0.bookID == book }.sorted { $0.lessonNumber < $1.lessonNumber }
    }
    public func words(in book: UUID) -> [Vocabulary] { words.filter { $0.bookID == book } }
    public func dueWords(at now: Date = Date()) -> [Vocabulary] {
        words.filter { ($0.progress.nextReviewDate ?? .distantFuture) <= now }
            .sorted { ($0.progress.nextReviewDate ?? .distantFuture) < ($1.progress.nextReviewDate ?? .distantFuture) }
    }
    public func validate() throws {
        guard databaseVersion == 1 else { throw AppError.unsupportedVersion(databaseVersion) }
        func unique<T: Identifiable>(_ values: [T], _ label: String) throws where T.ID: Hashable {
            guard Set(values.map(\.id)).count == values.count else { throw AppError.invalidData("\(label)包含重复 ID。") }
        }
        try unique(books, "词书"); try unique(chapters, "Lesson"); try unique(words, "单词")
        try unique(answers, "答题记录"); try unique(studySlices, "计时记录"); try unique(notes, "笔记"); try unique(chats, "问答")
        let bookIDs = Set(books.map(\.id)); let wordIDs = Set(words.map(\.id))
        let chapterMap = Dictionary(uniqueKeysWithValues: chapters.map { ($0.id, $0) })
        guard books.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              chapters.allSatisfy({ bookIDs.contains($0.bookID) && $0.lessonNumber > 0 }),
              words.allSatisfy({ bookIDs.contains($0.bookID) && chapterMap[$0.chapterID]?.bookID == $0.bookID
                  && !TextKey.normalize($0.word).isEmpty }) else { throw AppError.invalidData("词书、Lesson 与单词的关联不完整。") }
        guard settings.isValid, settings.mainBookID.map({ bookIDs.contains($0) }) ?? true,
              settings.lastWordID.map({ wordIDs.contains($0) }) ?? true else { throw AppError.invalidData("设置或当前学习位置无效。") }
        guard notes.allSatisfy({ wordIDs.contains($0.wordID) }),
              Set(notes.map(\.wordID)).count == notes.count,
              answers.allSatisfy({ wordIDs.contains($0.wordID) && $0.question.wordID == $0.wordID
                  && $0.id == $0.question.id && $0.isCorrect == $0.question.accepts($0.userAnswer) }),
              chats.allSatisfy({ ($0.wordID.map { wordIDs.contains($0) } ?? true) && ["user", "assistant"].contains($0.role) }),
              studySlices.allSatisfy({ $0.end >= $0.start && $0.duration <= 600 && $0.duration.isFinite })
        else { throw AppError.invalidData("学习记录、计时或笔记有损坏。") }
        for word in words {
            let p = word.progress
            guard p.correctCount >= 0, p.wrongCount >= 0, p.streakCorrect >= 0, p.streakWrong >= 0,
                  p.correctCount <= 1_000_000_000, p.wrongCount <= 1_000_000_000,
                  p.streakCorrect <= p.correctCount, p.streakWrong <= p.wrongCount,
                  !(p.streakCorrect > 0 && p.streakWrong > 0), p.intervalSeconds.isFinite,
                  (0...366 * 86400).contains(p.intervalSeconds), (1.3...2.8).contains(p.ease),
                  p.recentOutcomes.count <= 12 else { throw AppError.invalidData("\(word.word) 的复习状态不合法。") }
        }
        let grouped = Dictionary(grouping: answers, by: \.wordID)
        for word in words {
            let events = grouped[word.id] ?? []
            guard events.count == word.progress.totalAnswers,
                  events.filter(\.isCorrect).count == word.progress.correctCount,
                  events.filter(\.isFirstLearning).count == (events.isEmpty ? 0 : 1)
            else { throw AppError.invalidData("\(word.word) 的答题记录与累计次数不一致。") }
        }
        let slices = studySlices.sorted { $0.start < $1.start }
        for index in slices.indices.dropFirst() {
            guard slices[index].start >= slices[index - 1].end else { throw AppError.invalidData("计时记录发生重叠。") }
        }
    }
}
