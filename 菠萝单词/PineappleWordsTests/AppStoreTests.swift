import XCTest
import PineappleCore
@testable import PineappleWords

@MainActor
final class AppStoreTests: XCTestCase {
    private func store() -> AppStore {
        AppStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("StoreTests-\(UUID().uuidString)"))
    }
    private func populate(_ store: AppStore) throws -> Vocabulary {
        let details = Fixtures.snapshot().words.map(\.details)
        let preview = ImportValidator.preview(BookDraft(name: "离线测试词书", chapters: [ChapterDraft(lessonNumber: 1, words: details)]))
        XCTAssertTrue(store.importBook(preview))
        return try XCTUnwrap(store.snapshot.words.first)
    }
    func testSubmittingSameQuestionTwiceIsIdempotent() throws {
        let store = store(), word = try populate(store)
        let question = StudyQuestion(wordID: word.id, kind: .spelling, prompt: "我的", correctAnswer: word.word)
        let first = store.submit(question, answer: word.word, now: Fixtures.now)
        let second = store.submit(question, answer: word.word, now: Fixtures.now)
        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(store.snapshot.answers.count, 1)
        XCTAssertEqual(store.snapshot.words[0].progress.totalAnswers, 1)
    }
    func testQuestionWithChangedAnswerCannotBeRecorded() throws {
        let store = store(), word = try populate(store)
        let question = StudyQuestion(wordID: word.id, kind: .spelling, prompt: "我的", correctAnswer: "invented")
        XCTAssertNil(store.submit(question, answer: "invented"))
        XCTAssertEqual(store.snapshot.answers.count, 0)
    }
    func testDuplicateImportDoesNotCreateExtraData() throws {
        let store = store(); _ = try populate(store)
        let details = Fixtures.snapshot().words.map(\.details)
        let preview = ImportValidator.preview(BookDraft(name: "离线测试词书", chapters: [ChapterDraft(lessonNumber: 1, words: details)]))
        XCTAssertFalse(store.importBook(preview)); XCTAssertEqual(store.snapshot.books.count, 1)
    }
    func testFavoriteAndNoteSurviveReopeningAppStore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = AppStore(rootURL: root), word = try populate(first)
        XCTAssertTrue(first.editWord(word.id) { $0.isFavorite = true; $0.weakOverride = true })
        XCTAssertTrue(first.saveNote(wordID: word.id, text: "不要和 mine 混淆"))
        let reopened = AppStore(rootURL: root)
        XCTAssertTrue(try XCTUnwrap(reopened.snapshot.word(word.id)).isFavorite)
        XCTAssertEqual(reopened.snapshot.notes.first?.text, "不要和 mine 混淆")
    }
    func testIdleResumePreservesShortUncommittedTimeTail() {
        let store = store(), start = Date()
        XCTAssertTrue(store.ready)
        store.activity(at: start)
        XCTAssertTrue(store.flushTime(at: start.addingTimeInterval(175)))
        store.activity(at: start.addingTimeInterval(181))
        XCTAssertTrue(store.flushTime(at: start.addingTimeInterval(191)))
        XCTAssertEqual(store.snapshot.studySlices.reduce(0) { $0 + $1.duration }, 190, accuracy: 0.001)
    }
    func testMissingMeaningDoesNotConsumeNewWordGoal() throws {
        let store = store()
        store.updateSettings { $0.dailyNewGoal = 1 }
        var usable = LexicalDetails(word: "orchard")
        usable.meanings = ["果园"]
        let preview = ImportValidator.preview(BookDraft(name: "新词顺序测试", chapters: [
            ChapterDraft(lessonNumber: 1, words: [LexicalDetails(word: "unfinished"), usable])
        ]))
        XCTAssertTrue(store.importBook(preview))
        let expected = try XCTUnwrap(store.snapshot.words.first { $0.word == "orchard" })
        let session = StudySessionViewModel()
        session.start(store: store, scope: .newWords, preferred: .spelling)
        XCTAssertEqual(session.queue, [expected.id])
        XCTAssertEqual(session.question?.correctAnswer, "orchard")
    }
    func testFailedTimerWriteSurvivesBackgroundAndRetriesWithoutCountingGap() throws {
        let start = Date()
        var rejectWrite = true
        let store = AppStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) { slice, url in
            if rejectWrite { throw AppError.storage("模拟磁盘写入失败") }
            try StudyTimeJournal.write(slice, to: url)
        }
        XCTAssertTrue(store.ready)
        store.activity(at: start)
        store.foreground(false, at: start.addingTimeInterval(10))
        XCTAssertTrue(store.snapshot.studySlices.isEmpty)
        XCTAssertNotNil(store.errorMessage)
        rejectWrite = false
        store.foreground(true, at: start.addingTimeInterval(1010))
        store.activity(at: start.addingTimeInterval(1010))
        XCTAssertEqual(store.snapshot.studySlices.reduce(0) { $0 + $1.duration }, 10, accuracy: 0.001)
        XCTAssertTrue(store.flushTime(at: start.addingTimeInterval(1020)))
        XCTAssertTrue(store.flushTime(at: start.addingTimeInterval(1020)))
        XCTAssertEqual(store.snapshot.studySlices.reduce(0) { $0 + $1.duration }, 20, accuracy: 0.001)
    }
}
