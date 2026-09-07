import Foundation
import CryptoKit
import PineappleCore

struct BackupManifest: Codable, Sendable {
    var format: String = "pineapple-words-backup"
    var databaseVersion: Int
    var createdAt: Date
    var sha256: String
    var bookCount: Int
    var wordCount: Int
    var answerCount: Int
    var studySeconds: Double
    var apiKeyIncluded: Bool = false
}
struct BackupPreview: Identifiable, Sendable {
    var id = UUID()
    var manifest: BackupManifest
    var snapshot: AppSnapshot
}

enum BackupService {
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func encode(_ snapshot: AppSnapshot, now: Date = Date()) throws -> Data {
        try snapshot.validate()
        let payload = try JSONCoding.encoder().encode(snapshot)
        let manifest = BackupManifest(databaseVersion: 1, createdAt: now, sha256: digest(payload),
                                      bookCount: snapshot.books.count, wordCount: snapshot.words.count,
                                      answerCount: snapshot.answers.count,
                                      studySeconds: snapshot.studySlices.reduce(0) { $0 + $1.duration })
        return try StoredZIP.encode(["manifest.json": JSONCoding.encoder().encode(manifest), "data.json": payload])
    }
    static func decode(_ data: Data) throws -> BackupPreview {
        let entries = try StoredZIP.decode(data)
        guard Set(entries.keys) == Set(["manifest.json", "data.json"]),
              let manifestBytes = entries["manifest.json"], let payload = entries["data.json"] else {
            throw AppError.invalidData("备份缺少清单或数据库内容。")
        }
        let manifest = try JSONCoding.decoder().decode(BackupManifest.self, from: manifestBytes)
        guard manifest.format == "pineapple-words-backup", !manifest.apiKeyIncluded,
              digest(payload) == manifest.sha256 else { throw AppError.invalidData("备份的完整性校验未通过。") }
        let snapshot = try BackupMigrator.decode(payload, version: manifest.databaseVersion)
        guard snapshot.books.count == manifest.bookCount, snapshot.words.count == manifest.wordCount,
              snapshot.answers.count == manifest.answerCount, manifest.studySeconds.isFinite,
              abs(snapshot.studySlices.reduce(0) { $0 + $1.duration } - manifest.studySeconds) < 0.01
        else { throw AppError.invalidData("备份清单与学习数据不一致。") }
        return BackupPreview(manifest: manifest, snapshot: snapshot)
    }
    static func readFile(_ url: URL) throws -> Data {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
            result = Result {
                let size = try coordinated.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0 && size <= StoredZIP.maximumBytes else { throw AppError.invalidData("备份大小无效（最大 256 MB）。") }
                return try Data(contentsOf: coordinated)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw AppError.invalidData("无法读取备份，请先在“文件”中下载完整文件。") }
        return try result.get()
    }
    static func writeVerified(_ snapshot: AppSnapshot, to url: URL) throws {
        let data = try encode(snapshot)
        _ = try decode(data)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        _ = try decode(Data(contentsOf: url))
    }
    static func fileName(prefix: String = "菠萝单词备份", now: Date = Date()) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return "\(prefix)_\(formatter.string(from: now)).zip"
    }
}
