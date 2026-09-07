import Foundation

public struct ChapterDraft: Codable, Equatable, Sendable {
    public var lessonNumber: Int
    public var lessonName: String?
    public var words: [LexicalDetails]
    public init(lessonNumber: Int, lessonName: String? = nil, words: [LexicalDetails]) {
        self.lessonNumber = lessonNumber; self.lessonName = lessonName; self.words = words
    }
}
public struct BookDraft: Codable, Equatable, Sendable {
    public var name: String
    public var description: String?
    public var source: String?
    public var chapters: [ChapterDraft]
    public init(name: String, description: String? = nil, source: String? = nil, chapters: [ChapterDraft]) {
        self.name = name; self.description = description; self.source = source; self.chapters = chapters
    }
}
public struct ImportIssue: Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var lessonNumber: Int?
    public var word: String?
    public var message: String
    public init(lessonNumber: Int? = nil, word: String? = nil, message: String) {
        self.lessonNumber = lessonNumber; self.word = word; self.message = message
    }
}
public struct ImportPreview: Sendable {
    public var draft: BookDraft
    public var duplicateCount: Int
    public var failedCount: Int
    public var issues: [ImportIssue]
    public var wordCount: Int { draft.chapters.reduce(0) { $0 + $1.words.count } }
    public var canImport: Bool { !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && wordCount > 0 }
}

public enum ImportValidator {
    public static func preview(_ source: BookDraft, additionalFailures: Int = 0,
                               additionalIssues: [ImportIssue] = []) -> ImportPreview {
        var draft = source
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var issues = additionalIssues
        var duplicates = 0, failures = additionalFailures
        var result: [ChapterDraft] = []
        var merged: [Int: [LexicalDetails]] = [:]
        var names: [Int: String] = [:]
        for chapter in draft.chapters {
            guard chapter.lessonNumber > 0 else {
                failures += chapter.words.count
                issues.append(ImportIssue(message: "Lesson 编号必须大于 0；该章节未进入预览。")); continue
            }
            merged[chapter.lessonNumber, default: []].append(contentsOf: chapter.words)
            names[chapter.lessonNumber] = chapter.lessonName ?? "Lesson \(chapter.lessonNumber)"
        }
        var otherLessons: [String: Int] = [:]
        for number in merged.keys.sorted() {
            var seen: [String: LexicalDetails] = [:]
            var words: [LexicalDetails] = []
            for var entry in merged[number] ?? [] {
                entry.word = entry.word.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = TextKey.normalize(entry.word)
                guard !key.isEmpty, entry.word.count <= 120,
                      entry.word.rangeOfCharacter(from: .letters) != nil,
                      !entry.word.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                    failures += 1; issues.append(ImportIssue(lessonNumber: number, word: entry.word, message: "词条为空、过长或包含非法字符。")); continue
                }
                if let previous = seen[key] {
                    duplicates += 1
                    let conflict = previous.meanings != entry.meanings
                    issues.append(ImportIssue(lessonNumber: number, word: entry.word,
                                              message: conflict ? "同一 Lesson 重复且释义不同，暂保留首条；请核对。" : "同一 Lesson 重复，已保留首条。"))
                    continue
                }
                seen[key] = entry
                if let previous = otherLessons[key], previous != number {
                    issues.append(ImportIssue(lessonNumber: number, word: entry.word, message: "也出现在 Lesson \(previous)，保留各课词条，请核对语境。"))
                }
                otherLessons[key] = number
                if entry.coreMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(ImportIssue(lessonNumber: number, word: entry.word, message: "缺少中文释义；可导入，但普通练习会跳过。"))
                }
                if entry.word.range(of: "[A-Za-z]", options: .regularExpression) == nil {
                    issues.append(ImportIssue(lessonNumber: number, word: entry.word, message: "词条可能不是英文，请检查。"))
                }
                if let ipa = entry.ipa, !ipa.isEmpty, !(ipa.hasPrefix("/") && ipa.hasSuffix("/")) {
                    issues.append(ImportIssue(lessonNumber: number, word: entry.word, message: "音标缺少成对斜线；请检查是否为英式音标。"))
                }
                words.append(entry)
            }
            if !words.isEmpty { result.append(ChapterDraft(lessonNumber: number, lessonName: names[number], words: words)) }
        }
        if draft.name.isEmpty { issues.append(ImportIssue(message: "请填写词书名称。")) }
        draft.chapters = result
        return ImportPreview(draft: draft, duplicateCount: duplicates, failedCount: failures, issues: issues)
    }

    public static func materialize(_ preview: ImportPreview, fingerprint: String, now: Date = Date()) throws -> (Book, [Chapter], [Vocabulary]) {
        guard preview.canImport else { throw AppError.emptyBook }
        let book = Book(name: preview.draft.name, description: preview.draft.description ?? "", createdDate: now,
                        source: preview.draft.source ?? "个人导入", importFingerprint: fingerprint)
        var chapters: [Chapter] = [], words: [Vocabulary] = []
        for draft in preview.draft.chapters {
            let chapter = Chapter(bookID: book.id, lessonNumber: draft.lessonNumber,
                                  lessonName: draft.lessonName ?? "Lesson \(draft.lessonNumber)")
            chapters.append(chapter)
            words += draft.words.map { Vocabulary(bookID: book.id, chapterID: chapter.id, details: $0) }
        }
        return (book, chapters, words)
    }
}
