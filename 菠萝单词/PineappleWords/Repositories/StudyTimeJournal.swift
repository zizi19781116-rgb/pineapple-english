import Foundation
import PineappleCore

/// A tiny write-ahead file closes the gap between a timer checkpoint and the SQLite save.
/// It lives with its database generation, so a restored database never absorbs another generation's time.
enum StudyTimeJournal {
    static func write(_ slice: StudySlice, to url: URL) throws {
        try JSONCoding.encoder().encode(slice).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func read(_ url: URL) throws -> StudySlice? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let slice = try JSONCoding.decoder().decode(StudySlice.self, from: Data(contentsOf: url))
        guard slice.end >= slice.start, slice.duration <= 600, slice.duration.isFinite else {
            throw AppError.invalidData("未完成的计时记录损坏，原文件已保留。")
        }
        return slice
    }
    static func clear(_ url: URL) {
        // Leaving a committed entry is safe: replay checks its immutable ID.
        try? FileManager.default.removeItem(at: url)
    }
}
