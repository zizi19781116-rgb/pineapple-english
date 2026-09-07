import Foundation
import PineappleCore

private struct AIImportResponse: Decodable, Sendable {
    var book: BookDraft
    var unrecognized: [String]?
    var issues: [String]?
}
struct BookImportService {
    let ai: DeepSeekService
    static func chunks(_ text: String, limit: Int = 12000) -> [String] {
        var chunks: [String] = [], current = ""
        for line in text.components(separatedBy: .newlines) {
            if current.count + line.count + 1 > limit && !current.isEmpty { chunks.append(current); current = "" }
            if line.count > limit {
                var remainder = line[...]
                while !remainder.isEmpty {
                    let end = remainder.index(remainder.startIndex, offsetBy: min(limit, remainder.count))
                    chunks.append(String(remainder[..<end])); remainder = remainder[end...]
                }
            } else { current += line + "\n" }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { chunks.append(current) }
        return chunks
    }
    func analyse(text: String, name: String, settings: UserSettings, key: String,
                 progress: @MainActor (String) -> Void) async throws -> ImportPreview {
        let parts = Self.chunks(text)
        guard !parts.isEmpty else { throw AppError.emptyBook }
        var combined = BookDraft(name: name, source: "用户资料 · DeepSeek 辅助整理", chapters: [])
        var failures = 0, issues: [ImportIssue] = []
        for (index, part) in parts.enumerated() {
            try Task.checkCancellation()
            await progress("正在整理第 \(index + 1) / \(parts.count) 段")
            let carry = combined.chapters.last
            let instruction = AIPrompts.teacher + """
            \n只整理用户提供的资料，识别 Lesson 和词条。禁止凭记忆复原教材，禁止补写未出现的单词。
            不确定的音标、解释等字段留 null 或空数组，不补充猜测。
            如无 Lesson 信息，使用上一段章节；上一段也没有则使用 Lesson 1。
            上一段最后的 Lesson 编号：\(carry?.lessonNumber ?? 1)，课名：\(carry?.lessonName ?? "Lesson 1")。
            所有 words 条目结构为：\(AIPrompts.lexicalSchema)
            输出严格 JSON 对象：{"book":{"name":"词书名","description":null,"source":null,
            "chapters":[{"lessonNumber":1,"lessonName":"Lesson 1","words":[]}]},
            "unrecognized":["无法识别的词条或相关行"],"issues":["需要用户检查的问题"]}
            可忽略页码和纯排版文字。不要把正文每一个普通单词当作教材词表；没有明确词表时提取资料中明确要学习的词汇。
            """
            let result = try await ai.structured(AIImportResponse.self, task: .bookImport, question: "导入词书",
                                                 messages: [AIMessage(role: "system", content: instruction), AIMessage(role: "user", content: part)],
                                                 settings: settings, apiKey: key) { response in
                guard response.book.chapters.count <= 1000,
                      response.book.chapters.allSatisfy({ $0.lessonNumber > 0 && $0.words.count <= 3000 }) else {
                    throw AppError.invalidData("Lesson 编号或词条数量不合理。")
                }
            }
            for var chapter in result.book.chapters {
                chapter.words = chapter.words.filter { entry in
                    let pattern = "(?i)(?<![A-Za-z])" + NSRegularExpression.escapedPattern(for: entry.word) + "(?![A-Za-z])"
                    let found = (try? NSRegularExpression(pattern: pattern))?.firstMatch(in: part, range: NSRange(part.startIndex..., in: part)) != nil
                    if !found {
                        failures += 1; issues.append(ImportIssue(lessonNumber: chapter.lessonNumber, word: entry.word,
                                                                message: "AI 返回的单词未在该段原文中找到，已排除。"))
                    }
                    return found
                }
                combined.chapters.append(chapter)
            }
            failures += (result.unrecognized ?? []).count
            issues += (result.unrecognized ?? []).map { ImportIssue(message: "未识别：\($0)") }
            issues += (result.issues ?? []).map { ImportIssue(message: "AI 提醒：\($0)") }
        }
        return ImportValidator.preview(combined, additionalFailures: failures, additionalIssues: issues)
    }
}
