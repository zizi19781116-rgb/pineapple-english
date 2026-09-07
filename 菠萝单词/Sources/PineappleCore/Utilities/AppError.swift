import Foundation

public enum AppError: Error, LocalizedError, Equatable {
    case invalidData(String)
    case storage(String)
    case ai(String)
    case emptyBook
    case unsupportedVersion(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidData(let message): return "资料校验失败：\(message)"
        case .storage(let message): return "数据未保存：\(message)"
        case .ai(let message): return message
        case .emptyBook: return "词书没有可用单词，请先导入词表，或补全中文释义。"
        case .unsupportedVersion(let version): return "备份版本 \(version) 暂不支持。请使用与备份相同或更新版本的菠萝单词。"
        }
    }
}

public enum JSONCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Preserve Date's underlying Double exactly through disk/backup round trips.
        // Wire dates are seconds since 2001-01-01 00:00:00 UTC (Foundation reference date).
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .deferredToDate; return decoder
    }
}
