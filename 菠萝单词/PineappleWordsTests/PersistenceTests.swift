import XCTest
import SwiftData
import PineappleCore
@testable import PineappleWords

@MainActor
final class PersistenceTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func testSavedDatabaseSurvivesRepositoryReopen() throws {
        let url = try directory().appendingPathComponent("Learning.store")
        var snapshot = Fixtures.snapshot(); Fixtures.answer(&snapshot, correct: false)
        snapshot.notes = [WordNote(wordID: snapshot.words[0].id, text: "持久化笔记")]
        let writer = try LocalRepository(url: url); _ = try writer.load()
        try writer.save(snapshot, replacing: AppSnapshot())
        let reader = try LocalRepository(url: url)
        XCTAssertEqual(try reader.load().canonicalized, snapshot.canonicalized)
    }
    func testIncrementalSaveRetainsExistingAnswersAndNotes() throws {
        let repository = try LocalRepository(inMemory: true); _ = try repository.load()
        var initial = Fixtures.snapshot(); Fixtures.answer(&initial, correct: false)
        try repository.save(initial, replacing: AppSnapshot())
        var next = initial; Fixtures.answer(&next, correct: true, at: Fixtures.now.addingTimeInterval(60))
        next.notes.append(WordNote(wordID: next.words[0].id, text: "不能覆盖历史"))
        try repository.save(next, replacing: initial)
        XCTAssertEqual(try repository.load().canonicalized, next.canonicalized)
    }
    func testFullBackupIntegrityAndTamperRejection() throws {
        var snapshot = Fixtures.snapshot(); Fixtures.answer(&snapshot, correct: false)
        let bytes = try BackupService.encode(snapshot)
        let restored = try BackupService.decode(bytes)
        XCTAssertEqual(restored.snapshot, snapshot); XCTAssertFalse(restored.manifest.apiKeyIncluded)
        var contents = try StoredZIP.decode(bytes)
        contents["data.json"] = Data("{}".utf8)
        XCTAssertThrowsError(try BackupService.decode(StoredZIP.encode(contents)))
    }
    func testRestoreSwitchesGenerationAndPreservesOriginal() throws {
        let root = try directory(), coordinator = try StoreCoordinator(root: root)
        let (repository, empty) = try coordinator.open()
        var first = Fixtures.snapshot(); Fixtures.answer(&first, correct: true)
        try repository.save(first, replacing: empty)
        let originalPointer = try Data(contentsOf: root.appendingPathComponent("active-store.json"))
        var incoming = Fixtures.snapshot(); incoming.books[0].name = "迁入词书"
        let (_, restored) = try coordinator.activate(incoming)
        XCTAssertEqual(restored.canonicalized, incoming.canonicalized)
        XCTAssertNotEqual(try Data(contentsOf: root.appendingPathComponent("active-store.json")), originalPointer)
        XCTAssertEqual(try repository.load().canonicalized, first.canonicalized)
        XCTAssertEqual(try coordinator.open().1.canonicalized, incoming.canonicalized)
    }
    func testInvalidRestoreNeverChangesPointer() throws {
        let root = try directory(), coordinator = try StoreCoordinator(root: root)
        _ = try coordinator.open()
        let before = try Data(contentsOf: root.appendingPathComponent("active-store.json"))
        var invalid = Fixtures.snapshot(); invalid.words[0].bookID = UUID()
        XCTAssertThrowsError(try coordinator.activate(invalid))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("active-store.json")), before)
    }
    func testMissingActiveDatabaseDoesNotSilentlyCreateEmptyOne() throws {
        let root = try directory(), coordinator = try StoreCoordinator(root: root)
        let id = UUID().uuidString
        let pointer = StoreCoordinator.Pointer(formatVersion: 1, generation: id)
        try JSONEncoder().encode(pointer).write(to: root.appendingPathComponent("active-store.json"))
        XCTAssertThrowsError(try coordinator.open())
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(id).path))
    }
    func testTimerJournalRoundTripAndImmutableID() throws {
        let url = try directory().appendingPathComponent("pending-time.json")
        let slice = StudySlice(start: Fixtures.now, end: Fixtures.now.addingTimeInterval(15))
        try StudyTimeJournal.write(slice, to: url)
        XCTAssertEqual(try StudyTimeJournal.read(url), slice)
        StudyTimeJournal.clear(url); XCTAssertNil(try StudyTimeJournal.read(url))
    }
    func testMismatchedRowIdentityFailsWithoutDecodingIntoLiveState() throws {
        let repository = try LocalRepository(inMemory: true)
        let context = ModelContext(repository.container)
        let payload = try JSONCoding.encoder().encode(Fixtures.snapshot().words[0])
        context.insert(StoreSchemaV1.WordRow(id: UUID(), payload: payload))
        try context.save()
        XCTAssertThrowsError(try repository.load())
    }
    func testFingerprintRejectsIdenticalBookRegardlessOfWordOrder() throws {
        let details = Fixtures.snapshot().words.map(\.details)
        let first = BookDraft(name: "词书", chapters: [ChapterDraft(lessonNumber: 1, words: details)])
        let second = BookDraft(name: "词书", chapters: [ChapterDraft(lessonNumber: 1, words: Array(details.reversed()))])
        XCTAssertEqual(try AppStore.fingerprint(first), try AppStore.fingerprint(second))
    }
}
