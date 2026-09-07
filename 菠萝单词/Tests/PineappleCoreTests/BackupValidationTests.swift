import XCTest
@testable import PineappleCore

final class BackupValidationTests: XCTestCase {
    func testStandardCRCVector() { XCTAssertEqual(StoredZIP.crc32(Data("123456789".utf8)), 0xCBF43926) }
    func testZIPRoundTripPreservesAllBytes() throws {
        let entries = ["data.json": Data("{\"word\":\"我的\"}".utf8), "manifest.json": Data([0, 1, 2, 255])]
        XCTAssertEqual(try StoredZIP.decode(StoredZIP.encode(entries)), entries)
    }
    func testZIPRejectsTruncatedAndCorruptedBytes() throws {
        let archive = try StoredZIP.encode(["data.json": Data("123456789".utf8)])
        for length in [0, 1, 10, archive.count - 1] { XCTAssertThrowsError(try StoredZIP.decode(archive.prefix(length))) }
        var corrupted = archive; corrupted[39] ^= 0x01
        XCTAssertThrowsError(try StoredZIP.decode(corrupted))
    }
    func testZIPRejectsPathTraversalAndInvalidContainer() {
        XCTAssertThrowsError(try StoredZIP.encode(["../data.json": Data()]))
        XCTAssertThrowsError(try StoredZIP.encode(["a\\b": Data()]))
        XCTAssertThrowsError(try StoredZIP.decode(Data(repeating: 0, count: 100)))
    }
    func testFullDomainRoundTripIncludingHistoryAndManualOverrides() throws {
        var original = Fixtures.snapshot(); Fixtures.answer(&original, correct: false)
        original.words[0].isFavorite = true; original.words[0].confusingOverride = false; original.words[0].weakOverride = true
        original.notes = [WordNote(wordID: original.words[0].id, text: "容易与 mine 混淆", updatedAt: Fixtures.now)]
        original.chats = [ChatEntry(threadID: UUID(), wordID: original.words[0].id, role: "user", content: "为什么？", date: Fixtures.now, mode: .deep)]
        original.studySlices = [StudySlice(start: Fixtures.now, end: Fixtures.now.addingTimeInterval(120))]
        let decoded = try BackupMigrator.decode(JSONCoding.encoder().encode(original), version: 1)
        XCTAssertEqual(decoded, original)
    }
    func testDateRetainsFractionalPrecision() throws {
        var data = Fixtures.snapshot(); data.books[0].createdDate = Date(timeIntervalSinceReferenceDate: 810_345_123.1234567)
        XCTAssertEqual(try JSONCoding.decoder().decode(AppSnapshot.self, from: JSONCoding.encoder().encode(data)), data)
    }
    func testV0MigrationSuppliesDefaultsWithoutLosingLearning() throws {
        var data = Fixtures.snapshot(); Fixtures.answer(&data, correct: true)
        let encoded = try JSONCoding.encoder().encode(data)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["databaseVersion"] = 0; object.removeValue(forKey: "chats"); object.removeValue(forKey: "settings")
        let migrated = try BackupMigrator.decode(JSONSerialization.data(withJSONObject: object), version: 0)
        XCTAssertEqual(migrated.words, data.words); XCTAssertEqual(migrated.answers, data.answers)
        XCTAssertEqual(migrated.settings, UserSettings()); XCTAssertEqual(migrated.databaseVersion, 1)
    }
    func testFutureVersionRejected() { XCTAssertThrowsError(try BackupMigrator.decode(Data(), version: 999)) }
    func testOrphanedWordsAndDuplicateIDsRejected() {
        var data = Fixtures.snapshot(); data.words[0].chapterID = UUID()
        XCTAssertThrowsError(try data.validate())
        data = Fixtures.snapshot(); data.words.append(data.words[0])
        XCTAssertThrowsError(try data.validate())
    }
    func testAnswerCountersAndIncorrectLabelsMustMatchJournal() {
        var data = Fixtures.snapshot(); Fixtures.answer(&data, correct: false)
        data.words[0].progress.correctCount = 100
        XCTAssertThrowsError(try data.validate())
        data = Fixtures.snapshot(); Fixtures.answer(&data, correct: false); data.answers[0].isCorrect = true
        XCTAssertThrowsError(try data.validate())
    }
    func testOverlappingTimerSlicesRejected() {
        var data = Fixtures.snapshot()
        data.studySlices = [StudySlice(start: Fixtures.now, end: Fixtures.now.addingTimeInterval(60)),
                            StudySlice(start: Fixtures.now.addingTimeInterval(30), end: Fixtures.now.addingTimeInterval(90))]
        XCTAssertThrowsError(try data.validate())
    }
    func testInvalidSettingsAndReviewStateRejected() {
        var data = Fixtures.snapshot(); data.settings.idleTimeoutSeconds = 0
        XCTAssertThrowsError(try data.validate())
        data = Fixtures.snapshot(); data.words[0].progress.ease = .infinity
        XCTAssertThrowsError(try data.validate())
    }
}
