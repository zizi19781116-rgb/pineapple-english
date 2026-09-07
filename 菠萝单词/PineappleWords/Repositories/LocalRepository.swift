import Foundation
import SwiftData
import PineappleCore

@MainActor
final class LocalRepository {
    let container: ModelContainer
    private let context: ModelContext
    private var rowCache: [String: [UUID: any StoredRow]] = [:]
    private var available = true
    private let settingsID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))

    init(url: URL? = nil, inMemory: Bool = false) throws {
        let schema = Schema(versionedSchema: StoreSchemaV1.self)
        let configuration: ModelConfiguration
        if let url, !inMemory {
            configuration = ModelConfiguration("Pineapple", schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration("PineappleTests", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        container = try ModelContainer(for: schema, migrationPlan: StoreMigrationPlan.self, configurations: [configuration])
        context = ModelContext(container); context.autosaveEnabled = false
    }

    private func decode<T: Decodable, R: StoredRow>(_ type: T.Type, from row: R.Type) throws -> [T] {
        let rows = try context.fetch(FetchDescriptor<R>())
        var cache: [UUID: any StoredRow] = [:]
        var values: [T] = []
        for record in rows {
            guard cache[record.id] == nil else { throw AppError.invalidData("数据库包含重复主键，原文件已保留。") }
            let decoded = try JSONCoding.decoder().decode(type, from: record.payload)
            if let object = try JSONSerialization.jsonObject(with: record.payload) as? [String: Any], let id = object["id"] as? String {
                guard UUID(uuidString: id) == record.id else { throw AppError.invalidData("数据库记录 ID 与内容不一致。") }
            }
            cache[record.id] = record; values.append(decoded)
        }
        rowCache[String(reflecting: row)] = cache
        return values
    }
    func load() throws -> AppSnapshot {
        var data = AppSnapshot()
        data.books = try decode(Book.self, from: StoreSchemaV1.BookRow.self).sorted { $0.createdDate < $1.createdDate }
        data.chapters = try decode(Chapter.self, from: StoreSchemaV1.ChapterRow.self).sorted { $0.lessonNumber < $1.lessonNumber }
        data.words = try decode(Vocabulary.self, from: StoreSchemaV1.WordRow.self).sorted { $0.word.localizedStandardCompare($1.word) == .orderedAscending }
        data.answers = try decode(AnswerEvent.self, from: StoreSchemaV1.AnswerRow.self).sorted { $0.date < $1.date }
        data.studySlices = try decode(StudySlice.self, from: StoreSchemaV1.TimeRow.self).sorted { $0.start < $1.start }
        data.notes = try decode(WordNote.self, from: StoreSchemaV1.NoteRow.self).sorted { $0.updatedAt < $1.updatedAt }
        data.chats = try decode(ChatEntry.self, from: StoreSchemaV1.ChatRow.self).sorted { $0.date < $1.date }
        let settings = try decode(UserSettings.self, from: StoreSchemaV1.SettingsRow.self)
        guard settings.count <= 1 else { throw AppError.invalidData("发现重复设置记录。") }
        data.settings = settings.first ?? UserSettings()
        try data.validate()
        return data
    }

    private func sync<T: Codable & Equatable & Identifiable, R: StoredRow>(
        _ values: [T], old: [T], row: R.Type
    ) throws where T.ID == UUID {
        let key = String(reflecting: row)
        var cache = rowCache[key] ?? [:]
        let previous = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let newIDs = Set(values.map(\.id))
        for value in values where previous[value.id] != value {
            let bytes = try JSONCoding.encoder().encode(value)
            if let existing = cache[value.id] as? R { existing.payload = bytes }
            else { let record = R(id: value.id, payload: bytes); context.insert(record); cache[value.id] = record }
        }
        for id in Array(cache.keys) where !newIDs.contains(id) {
            if let record = cache[id] as? R { context.delete(record) }; cache[id] = nil
        }
        rowCache[key] = cache
    }

    /// One save commits answers, review state and settings together. Rollback restores the old state.
    func save(_ next: AppSnapshot, replacing old: AppSnapshot) throws {
        guard available else { throw AppError.storage("数据库回读失败，请重新打开 App 进入恢复流程。原数据未被清空。") }
        do {
            try sync(next.books, old: old.books, row: StoreSchemaV1.BookRow.self)
            try sync(next.chapters, old: old.chapters, row: StoreSchemaV1.ChapterRow.self)
            try sync(next.words, old: old.words, row: StoreSchemaV1.WordRow.self)
            try sync(next.answers, old: old.answers, row: StoreSchemaV1.AnswerRow.self)
            try sync(next.studySlices, old: old.studySlices, row: StoreSchemaV1.TimeRow.self)
            try sync(next.notes, old: old.notes, row: StoreSchemaV1.NoteRow.self)
            try sync(next.chats, old: old.chats, row: StoreSchemaV1.ChatRow.self)
            let key = String(reflecting: StoreSchemaV1.SettingsRow.self)
            if next.settings != old.settings || rowCache[key]?.isEmpty != false {
                let payload = try JSONCoding.encoder().encode(next.settings)
                if let row = rowCache[key]?[settingsID] as? StoreSchemaV1.SettingsRow { row.payload = payload }
                else {
                    let row = StoreSchemaV1.SettingsRow(id: settingsID, payload: payload)
                    context.insert(row); rowCache[key] = [settingsID: row]
                }
            }
            try context.save()
        } catch {
            context.rollback()
            rowCache.removeAll()
            do { _ = try load() } catch { available = false }
            throw AppError.storage("\(error.localizedDescription) 请检查设备剩余空间，然后重试。")
        }
    }
}
