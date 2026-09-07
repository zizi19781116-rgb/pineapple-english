import XCTest
@testable import PineappleCore

final class QuestionTests: XCTestCase {
    func testFourOptionsAreDistinctAndContainCorrectMeaning() throws {
        let data = Fixtures.snapshot()
        let question = try QuestionFactory.make(word: data.words[0], pool: data.words, preferred: .choice, hard: false)
        XCTAssertEqual(question.kind, .choice); XCTAssertEqual(Set(question.options).count, 4)
        XCTAssertTrue(question.options.contains("我的"))
    }
    func testInsufficientDistractorsUsesSpelling() throws {
        let data = Fixtures.snapshot()
        let question = try QuestionFactory.make(word: data.words[0], pool: [data.words[0]], preferred: .choice, hard: false)
        XCTAssertEqual(question.kind, .spelling)
        XCTAssertTrue(question.hint?.contains("This is ___ book.") ?? false)
        XCTAssertFalse(question.hint?.contains("This is my book.") ?? true)
    }
    func testEquivalentMeaningNotUsedAsDistractor() throws {
        var data = Fixtures.snapshot(); data.words[1].details.meanings = [" 我的 "]
        let question = try QuestionFactory.make(word: data.words[0], pool: data.words, preferred: .choice, hard: false)
        XCTAssertEqual(question.kind, .spelling)
    }
    func testHardClozeContainsNoChineseOrInitialHint() throws {
        let data = Fixtures.snapshot()
        let question = try QuestionFactory.make(word: data.words[0], pool: data.words, preferred: .spelling, hard: true)
        XCTAssertEqual(question.prompt, "This is ___ book."); XCTAssertNil(question.hint)
    }
    func testClozeUsesWholeWordAndDoesNotReplaceSubstring() {
        XCTAssertNil(QuestionFactory.cloze("This is a myth.", answer: "my"))
        XCTAssertEqual(QuestionFactory.cloze("MY book is here.", answer: "my"), "___ book is here.")
    }
    func testAnswerNormalisationRetainsMeaningfulPunctuation() {
        let question = StudyQuestion(wordID: UUID(), kind: .spelling, prompt: "", correctAnswer: "don't")
        XCTAssertTrue(question.accepts("  DON’T\n")); XCTAssertFalse(question.accepts("dont"))
    }
    func testAIAnswerCannotChangeToMine() {
        let word = Fixtures.snapshot().words[0]
        let draft = AIQuestionDraft(prompt: "This is ___ book.", correctAnswer: "mine", explanation: "", sourceQuote: "This is my book.")
        XCTAssertThrowsError(try draft.validated(for: word))
    }
    func testAIRequiresVerbatimSourceAndNoAnswerLeak() {
        let word = Fixtures.snapshot().words[0]
        XCTAssertThrowsError(try AIQuestionDraft(prompt: "___", correctAnswer: "my", explanation: "", sourceQuote: "invented").validated(for: word))
        XCTAssertThrowsError(try AIQuestionDraft(prompt: "Choose my or my: ___", correctAnswer: "my", explanation: "", sourceQuote: "my book").validated(for: word))
        XCTAssertNoThrow(try AIQuestionDraft(prompt: "This is ___ book.", correctAnswer: "my", explanation: "修饰名词。", sourceQuote: "This is my book.").validated(for: word))
    }
    func testAIRoutingHonoursForcedDepth() {
        XCTAssertEqual(AIRouter.resolve(.auto, task: .chat, question: "apple 是什么意思"), .fast)
        XCTAssertEqual(AIRouter.resolve(.auto, task: .chat, question: "为什么这里必须使用 have been 而不能使用 had been"), .deep)
        XCTAssertEqual(AIRouter.resolve(.fast, task: .bookImport, question: "a"), .deep)
        XCTAssertEqual(AIRouter.resolve(.fast, task: .hardQuestion, question: "a"), .deep)
        XCTAssertEqual(AIRouter.resolve(.fast, task: .chat, question: "为什么？"), .fast)
    }
}
