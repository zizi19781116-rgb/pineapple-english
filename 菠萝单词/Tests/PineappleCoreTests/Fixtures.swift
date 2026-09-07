import Foundation
import PineappleCore

enum Fixtures {
    static let now = Date(timeIntervalSince1970: 1_789_000_000)
    static func snapshot() -> AppSnapshot {
        var data = AppSnapshot()
        let book = Book(name: "测试专用词书", createdDate: now)
        let chapter = Chapter(bookID: book.id, lessonNumber: 1, lessonName: "Lesson 1")
        data.books = [book]; data.chapters = [chapter]
        let values = [
            LexicalDetails(word: "my", ipa: "/maɪ/", part_of_speech: ["形容词性物主代词"], meanings: ["我的"],
                           english_definition: "belonging to the speaker", phrases: ["my book"],
                           examples: [ExampleSentence(english: "This is my book.", chinese: "这是我的书。")]),
            LexicalDetails(word: "your", meanings: ["你的"]),
            LexicalDetails(word: "our", meanings: ["我们的"]),
            LexicalDetails(word: "their", meanings: ["他们的"])
        ]
        data.words = values.map { Vocabulary(bookID: book.id, chapterID: chapter.id, details: $0) }
        data.settings.mainBookID = book.id
        return data
    }
    static func answer(_ data: inout AppSnapshot, index: Int = 0, correct: Bool, at date: Date = now) {
        let word = data.words[index]
        let question = StudyQuestion(wordID: word.id, kind: .spelling, prompt: word.details.coreMeaning, correctAnswer: word.word)
        let event = AnswerEvent(question: question, answer: correct ? word.word : "wrong", date: date, isFirstLearning: word.progress.totalAnswers == 0)
        ReviewEngine.record(&data.words[index], correct: correct, at: date, removalStreak: data.settings.mistakeRemovalStreak)
        data.answers.append(event)
    }
}
