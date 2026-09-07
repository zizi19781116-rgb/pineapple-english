import Foundation

public enum BackupMigrator {
    public static func decode(_ data: Data, version: Int) throws -> AppSnapshot {
        guard (0...1).contains(version) else { throw AppError.unsupportedVersion(version) }
        var bytes = data
        if version == 0 {
            // V0 development export: same learning records, before chat history/settings defaults.
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (object["databaseVersion"] as? Int) == 0 else { throw AppError.invalidData("旧备份版本标记不一致。") }
            object["databaseVersion"] = 1
            if object["chats"] == nil { object["chats"] = [] }
            if object["settings"] == nil { object["settings"] = [:] }
            bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }
        let snapshot = try JSONCoding.decoder().decode(AppSnapshot.self, from: bytes)
        guard snapshot.databaseVersion == 1 else { throw AppError.invalidData("备份版本与内容不一致。") }
        try snapshot.validate()
        return snapshot
    }
}
