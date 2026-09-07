import Foundation
import Combine
import PineappleCore

@MainActor
final class BookImportViewModel: ObservableObject {
    @Published var name = "我的词书"
    @Published var sourceText = ""
    @Published var useAI = true
    @Published var fileExtension = "txt"
    @Published var preview: ImportPreview?
    @Published var working = false
    @Published var progressText = ""
    @Published var errorMessage: String?
    private var task: Task<Void, Never>?
    private var sourceFailures = 0
    private var sourceDuplicates = 0
    private var sourceIssues: [ImportIssue] = []

    func load(_ url: URL) {
        task?.cancel(); working = true; errorMessage = nil; progressText = "正在读取资料，扫描 PDF 会在设备上识别文字…"
        task = Task {
            defer { working = false }
            do {
                let extraction = Task.detached(priority: .userInitiated) { try SourceReader.read(url) }
                let result = try await withTaskCancellationHandler(operation: { try await extraction.value }, onCancel: { extraction.cancel() })
                try Task.checkCancellation()
                sourceText = result.text; fileExtension = result.fileExtension
                name = url.deletingPathExtension().lastPathComponent
                useAI = !["csv", "json"].contains(result.fileExtension); preview = nil
            } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
        }
    }
    func analyse(store: AppStore) {
        guard !working else { return }
        let text = sourceText, bookName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errorMessage = "请先选择文件或粘贴资料。"; return }
        guard !bookName.isEmpty else { errorMessage = "请填写词书名称。"; return }
        guard text.count <= 500_000 else { errorMessage = "资料超过 50 万字，请分册导入。"; return }
        let settings = store.snapshot.settings
        working = true; errorMessage = nil; progressText = "正在检查资料…"
        task = Task {
            defer { working = false }
            do {
                let result: ImportPreview
                if useAI {
                    guard let key = try KeychainService.read(), !key.isEmpty else { throw AppError.ai("请先在设置中保存 DeepSeek API Key，或关闭 AI 整理使用本地解析。") }
                    result = try await BookImportService(ai: store.ai).analyse(text: text, name: bookName, settings: settings, key: key) { [weak self] in self?.progressText = $0 }
                } else if fileExtension == "json" {
                    let draft = try JSONDecoder().decode(BookDraft.self, from: Data(text.utf8))
                    var named = draft; named.name = bookName
                    result = ImportValidator.preview(named)
                } else if fileExtension == "csv" {
                    result = try CSVParser.book(text, name: bookName)
                } else { result = PlainTextParser.book(text, name: bookName) }
                try Task.checkCancellation()
                sourceFailures = result.failedCount; sourceDuplicates = result.duplicateCount; sourceIssues = result.issues
                preview = result
            } catch is CancellationError {} catch let error as DecodingError {
                errorMessage = "JSON 与词书格式不一致。需要 name、chapters、lessonNumber 和 words。请检查字段类型，或打开 AI 整理。\n\(error.localizedDescription)"
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func rename(_ name: String) { guard var current = preview else { return }; current.draft.name = name; preview = current }
    func editWord(chapter: Int, word: Int, details: LexicalDetails) {
        guard var draft = preview?.draft, draft.chapters.indices.contains(chapter), draft.chapters[chapter].words.indices.contains(word) else { return }
        draft.chapters[chapter].words[word] = details
        revalidate(draft)
    }
    func removeWord(chapter: Int, word: Int) {
        guard var draft = preview?.draft, draft.chapters.indices.contains(chapter), draft.chapters[chapter].words.indices.contains(word) else { return }
        draft.chapters[chapter].words.remove(at: word); revalidate(draft)
    }
    func editChapter(index: Int, number: Int, name: String) {
        guard var draft = preview?.draft, draft.chapters.indices.contains(index), number > 0 else { return }
        draft.chapters[index].lessonNumber = number
        draft.chapters[index].lessonName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Lesson \(number)" : name
        revalidate(draft)
    }
    func removeChapter(index: Int) {
        guard var draft = preview?.draft, draft.chapters.indices.contains(index) else { return }
        draft.chapters.remove(at: index); revalidate(draft)
    }
    private func revalidate(_ draft: BookDraft) {
        var validated = ImportValidator.preview(draft)
        validated.failedCount += sourceFailures; validated.duplicateCount += sourceDuplicates
        validated.issues = sourceIssues + validated.issues
        preview = validated
    }
    func cancel() { task?.cancel() }
    func backToSource() { preview = nil; errorMessage = nil }
}
