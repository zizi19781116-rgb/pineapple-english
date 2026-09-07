import XCTest
@testable import PineappleCore

final class ImportTests: XCTestCase {
    func testCSVHandlesBOMQuotesCommaAndEmbeddedNewline() throws {
        let input = "\u{FEFF}word,meaning,example\r\nmy,我的,\"This is my book,\nmy pen.\"\r\n"
        let preview = try CSVParser.book(input, name: "词书")
        XCTAssertEqual(preview.wordCount, 1)
        XCTAssertEqual(preview.draft.chapters[0].words[0].examples?.first?.english, "This is my book,\nmy pen.")
    }
    func testEscapedCSVQuotes() throws {
        XCTAssertEqual(try CSVParser.rows("a,b\n\"a\"\"b\",c"), [["a", "b"], ["a\"b", "c"]])
    }
    func testMalformedCSVIsRejectedOrReported() throws {
        XCTAssertThrowsError(try CSVParser.rows("word,meaning\n\"my,我的"))
        XCTAssertThrowsError(try CSVParser.rows("word\n\"my\"bad"))
        let preview = try CSVParser.book("word,meaning,lesson\nmy,我的,not-a-number\nyour,你的\nour,我们的,1", name: "词书")
        XCTAssertEqual(preview.failedCount, 2); XCTAssertEqual(preview.wordCount, 1)
    }
    func testDuplicateCSVHeadersAreRejected() { XCTAssertThrowsError(try CSVParser.book("word,word\nmy,my", name: "词书")) }
    func testDeduplicationKeepsCrossLessonContext() {
        let draft = BookDraft(name: "词书", chapters: [
            ChapterDraft(lessonNumber: 1, words: [LexicalDetails(word: "my", meanings: ["我的"]), LexicalDetails(word: " MY ", meanings: ["我的"])]),
            ChapterDraft(lessonNumber: 2, words: [LexicalDetails(word: "my", meanings: ["我的"])])
        ])
        let preview = ImportValidator.preview(draft)
        XCTAssertEqual(preview.duplicateCount, 1); XCTAssertEqual(preview.wordCount, 2)
        XCTAssertTrue(preview.issues.contains { $0.message.contains("也出现在") })
    }
    func testMissingOptionalFieldsDecode() throws {
        let detail = try JSONDecoder().decode(LexicalDetails.self, from: Data("{\"word\":\"my\"}".utf8))
        XCTAssertNil(detail.ipa); XCTAssertNil(detail.meanings)
        let preview = ImportValidator.preview(BookDraft(name: "空字段", chapters: [ChapterDraft(lessonNumber: 1, words: [detail])]))
        XCTAssertEqual(preview.wordCount, 1); XCTAssertTrue(preview.issues.contains { $0.message.contains("缺少中文") })
    }
    func testInvalidWordsAndEmptyBooksCannotSlipThrough() {
        let preview = ImportValidator.preview(BookDraft(name: "", chapters: [ChapterDraft(lessonNumber: 1, words: [LexicalDetails(word: ""), LexicalDetails(word: "123")])]))
        XCTAssertEqual(preview.failedCount, 2); XCTAssertFalse(preview.canImport)
        XCTAssertThrowsError(try ImportValidator.materialize(preview, fingerprint: "x"))
    }
    func testOfflineLessonParsing() {
        let preview = PlainTextParser.book("Lesson 1\nmy\t我的\nLesson 2\nyour\t你的", name: "词表")
        XCTAssertEqual(preview.draft.chapters.count, 2); XCTAssertEqual(preview.wordCount, 2)
    }
    func testMaterializedBookHasConsistentLinks() throws {
        let preview = PlainTextParser.book("Lesson 1\nmy\t我的", name: "词表")
        let (book, chapters, words) = try ImportValidator.materialize(preview, fingerprint: "fixed")
        var snapshot = AppSnapshot(); snapshot.books = [book]; snapshot.chapters = chapters; snapshot.words = words
        XCTAssertNoThrow(try snapshot.validate())
    }
}
