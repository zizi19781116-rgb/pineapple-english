import Foundation

public enum CSVParser {
    /// RFC 4180 quoting, escaped quotes, embedded line breaks, BOM, CRLF and LF.
    public static func rows(_ input: String) throws -> [[String]] {
        let characters = Array(input.replacingOccurrences(of: "\u{FEFF}", with: ""))
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, closedQuote = false, index = 0
        func finishField() { row.append(field); field = ""; closedQuote = false }
        func finishRow() { finishField(); if row.contains(where: { !$0.isEmpty }) { rows.append(row) }; row = [] }
        while index < characters.count {
            let c = characters[index]
            if quoted {
                if c == "\"" {
                    if index + 1 < characters.count && characters[index + 1] == "\"" { field.append("\""); index += 1 }
                    else { quoted = false; closedQuote = true }
                } else { field.append(c) }
            } else if c == "," { finishField() }
            else if c == "\r\n" || c == "\n" || c == "\r" {
                if c == "\r" && index + 1 < characters.count && characters[index + 1] == "\n" { index += 1 }
                finishRow()
            } else if c == "\"" {
                guard field.isEmpty && !closedQuote else { throw AppError.invalidData("CSV 引号位置错误。") }
                quoted = true
            } else {
                guard !closedQuote || c == " " || c == "\t" else { throw AppError.invalidData("CSV 引号结束后有多余字符。") }
                if !closedQuote { field.append(c) }
            }
            index += 1
        }
        guard !quoted else { throw AppError.invalidData("CSV 存在未闭合的引号。") }
        if !field.isEmpty || !row.isEmpty || closedQuote { finishRow() }
        return rows
    }

    public static func book(_ text: String, name: String) throws -> ImportPreview {
        let rows = try rows(text)
        guard let headers = rows.first else { throw AppError.emptyBook }
        let keys = headers.map(TextKey.normalize)
        guard Set(keys).count == keys.count else { throw AppError.invalidData("CSV 表头重复。") }
        func column(_ options: [String]) -> Int? { keys.firstIndex { options.contains($0) } }
        guard let wordColumn = column(["word", "单词", "英文"]) else { throw AppError.invalidData("CSV 需要 word（或“单词”）表头。") }
        let meaningColumn = column(["meaning", "meanings", "中文", "释义", "核心中文义"])
        let lessonColumn = column(["lesson", "lessonnumber", "lesson_number", "课号", "章节"])
        let lessonNameColumn = column(["lessonname", "lesson_name", "课名"])
        let ipaColumn = column(["ipa", "british ipa", "音标"])
        let posColumn = column(["part_of_speech", "pos", "词性"])
        let exampleColumn = column(["example", "例句"])
        let definitionColumn = column(["english_definition", "英文释义"])
        let phraseColumn = column(["phrases", "词组"])
        var chapters: [Int: ChapterDraft] = [:], failures = 0
        var issues: [ImportIssue] = []
        for (index, row) in rows.dropFirst().enumerated() {
            guard row.count == headers.count else {
                failures += 1; issues.append(ImportIssue(message: "CSV 第 \(index + 2) 行列数与表头不一致。")); continue
            }
            func value(_ column: Int?) -> String? {
                guard let column else { return nil }
                let value = row[column].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            let lessonText = value(lessonColumn)
            let number = lessonText.flatMap(Int.init) ?? (lessonText == nil ? 1 : 0)
            guard number > 0 else { failures += 1; issues.append(ImportIssue(message: "CSV 第 \(index + 2) 行课号不是正整数。")); continue }
            let detail = LexicalDetails(word: row[wordColumn], ipa: value(ipaColumn),
                                        part_of_speech: value(posColumn).map { [$0] }, meanings: value(meaningColumn).map { [$0] },
                                        english_definition: value(definitionColumn),
                                        phrases: value(phraseColumn).map { $0.components(separatedBy: "|") },
                                        examples: value(exampleColumn).map { [ExampleSentence(english: $0)] })
            if chapters[number] == nil { chapters[number] = ChapterDraft(lessonNumber: number, lessonName: value(lessonNameColumn), words: []) }
            chapters[number]?.words.append(detail)
        }
        return ImportValidator.preview(BookDraft(name: name, source: "CSV 文件", chapters: chapters.values.sorted { $0.lessonNumber < $1.lessonNumber }),
                                       additionalFailures: failures, additionalIssues: issues)
    }
}
