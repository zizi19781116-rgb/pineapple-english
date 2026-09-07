import Foundation
import PineappleCore

@MainActor
final class StoreCoordinator {
    struct Pointer: Codable { let formatVersion: Int; let generation: String }
    let root: URL
    private var pointerURL: URL { root.appendingPathComponent("active-store.json") }
    var recoveryDirectory: URL { root.appendingPathComponent("Recovery", isDirectory: true) }
    func timeJournalURL() throws -> URL {
        let pointer = try JSONDecoder().decode(Pointer.self, from: Data(contentsOf: pointerURL))
        return try databaseURL(pointer.generation).deletingLastPathComponent().appendingPathComponent("pending-time.json")
    }

    init(root: URL? = nil) throws {
        let base = try root ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true).appendingPathComponent("PineappleWords", isDirectory: true)
        self.root = base
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
    }

    private func databaseURL(_ generation: String) throws -> URL {
        guard UUID(uuidString: generation) != nil else { throw AppError.invalidData("数据库索引损坏。") }
        return root.appendingPathComponent(generation, isDirectory: true).appendingPathComponent("Learning.store")
    }
    func open() throws -> (LocalRepository, AppSnapshot) {
        if FileManager.default.fileExists(atPath: pointerURL.path) {
            let pointer = try JSONDecoder().decode(Pointer.self, from: Data(contentsOf: pointerURL))
            guard pointer.formatVersion == 1 else { throw AppError.invalidData("数据库索引版本不支持。") }
            let url = try databaseURL(pointer.generation)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw AppError.storage("原数据库文件缺失。请选择恢复备份；不会创建空数据库覆盖记录。")
            }
            let repository = try LocalRepository(url: url)
            return (repository, try repository.load())
        }
        let children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        guard !children.contains(where: { UUID(uuidString: $0.lastPathComponent) != nil }) else {
            throw AppError.storage("存在历史数据库但索引缺失。请从恢复页面导出原文件或迁入备份。")
        }
        return try activate(AppSnapshot())
    }

    /// A failed prepare/save/readback never alters the active generation or its SQLite/WAL files.
    func activate(_ snapshot: AppSnapshot) throws -> (LocalRepository, AppSnapshot) {
        try snapshot.validate()
        let generation = UUID().uuidString
        let url = try databaseURL(generation)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let staged = try LocalRepository(url: url)
        _ = try staged.load()
        try staged.save(snapshot, replacing: AppSnapshot())
        let verification = try LocalRepository(url: url)
        let verified = try verification.load()
        try verified.validate()
        guard verified.canonicalized == snapshot.canonicalized
        else { throw AppError.storage("新数据库读回校验未通过，原数据库仍保留。") }
        let pointer = try JSONEncoder().encode(Pointer(formatVersion: 1, generation: generation))
        try pointer.write(to: pointerURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return (verification, verified)
    }
    func localBackups() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: recoveryDirectory,
                                                                 includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "zip" }.map { url in
            (url: url, date: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }.sorted {
            $0.date == $1.date ? $0.url.lastPathComponent > $1.url.lastPathComponent : $0.date > $1.date
        }.map { $0.url }
    }
}
