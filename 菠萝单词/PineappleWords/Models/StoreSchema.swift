import Foundation
import SwiftData

protocol StoredRow: PersistentModel {
    var id: UUID { get set }
    var payload: Data { get set }
    init(id: UUID, payload: Data)
}

/// Each table has stable IDs. Domain fields use a versioned, inspectable JSON payload.
/// This keeps backup format and review algorithms independent of persistence macros.
enum StoreSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [BookRow.self, ChapterRow.self, WordRow.self, AnswerRow.self, TimeRow.self,
         NoteRow.self, ChatRow.self, SettingsRow.self]
    }
    @Model final class BookRow: StoredRow {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(id: UUID, payload: Data) { self.id = id; self.payload = payload }
    }
    @Model final class ChapterRow: StoredRow {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(id: UUID, payload: Data) { self.id = id; self.payload = payload }
    }
    @Model final class WordRow: StoredRow {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(id: UUID, payload: Data) { self.id = id; self.payload = payload }
    }
    @Model final class AnswerRow: StoredRow {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(id: UUID, payload: Data) { self.id = id; self.payload = payload }
    }
    @Model final class TimeRow: StoredRow {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(id: UUID, payload: Data) { self.id = id; self.payload = payload }
    }
    @Model final class NoteRow: StoredRow {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(id: UUID, payload: Data) { self.id = id; self.payload = payload }
    }
    @Model final class ChatRow: StoredRow {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(id: UUID, payload: Data) { self.id = id; self.payload = payload }
    }
    @Model final class SettingsRow: StoredRow {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(id: UUID, payload: Data) { self.id = id; self.payload = payload }
    }
}

enum StoreMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [StoreSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
    // Add V2 and an explicit stage here. Never edit V1's stored-property types in place.
}
