import Foundation

public enum PlainTextParser {
    /// Offline convention: Lesson N / 课程 N headings, then word<TAB>Chinese meaning.
    public static func book(_ text: String, name: String) -> ImportPreview {
        var chapters: [Int: ChapterDraft] = [:], number = 1, failures = 0
        var issues: [ImportIssue] = []
        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if let regex = try? NSRegularExpression(pattern: "(?i)^(?:lesson|课程|第)\\s*(\\d+)\\s*(?:课)?(?:\\s|:|：|$)(.*)$"),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let range = Range(match.range(at: 1), in: line), let value = Int(line[range]), value > 0 {
                number = value
                if chapters[number] == nil { chapters[number] = ChapterDraft(lessonNumber: number, lessonName: line, words: []) }
                continue
            }
            let fields = line.components(separatedBy: "\t")
            guard fields.count == 1 || fields.count == 2 else {
                failures += 1; issues.append(ImportIssue(message: "文本第 \(index + 1) 行不符合“英文 + Tab + 中文”的格式。")); continue
            }
            if fields.count == 1 && (line.count > 100 || line.contains("[资料第")) {
                failures += 1; issues.append(ImportIssue(message: "文本第 \(index + 1) 行无法作为词条，请使用 AI 整理或修订文本。")); continue
            }
            if chapters[number] == nil { chapters[number] = ChapterDraft(lessonNumber: number, words: []) }
            let meanings = fields.count == 2 ? [fields[1]] : nil
            chapters[number]?.words.append(LexicalDetails(word: fields[0], meanings: meanings))
        }
        return ImportValidator.preview(BookDraft(name: name, source: "本地文本解析", chapters: chapters.values.sorted { $0.lessonNumber < $1.lessonNumber }),
                                       additionalFailures: failures, additionalIssues: issues)
    }
}
