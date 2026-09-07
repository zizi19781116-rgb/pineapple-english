import SwiftUI
import UniformTypeIdentifiers
import PineappleCore

private struct ImportWordSelection: Identifiable {
    var id = UUID()
    var chapter: Int
    var word: Int
    var details: LexicalDetails
}
private struct ImportChapterSelection: Identifiable {
    var id = UUID()
    var index: Int
    var number: Int
    var name: String
}
@MainActor
struct BookImportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = BookImportViewModel()
    @State private var chooseFile = false
    @State private var editing: ImportWordSelection?
    @State private var acknowledged = false
    @State private var chapterEditing: ImportChapterSelection?
    var body: some View {
        Group {
            if let preview = model.preview { previewBody(preview) }
            else { sourceBody }
        }
        .navigationTitle(model.preview == nil ? "导入词书" : "检查导入预览").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { model.cancel(); dismiss() } }
        }
        .fileImporter(isPresented: $chooseFile, allowedContentTypes: [.plainText, .commaSeparatedText, .json, .pdf]) { result in
            switch result { case .success(let url): model.load(url); case .failure(let error): model.errorMessage = error.localizedDescription }
        }
        .sheet(item: $editing) { selection in
            NavigationStack {
                ImportWordEditor(details: selection.details) { details in
                    model.editWord(chapter: selection.chapter, word: selection.word, details: details)
                    editing = nil; acknowledged = false
                }
            }
        }
        .sheet(item: $chapterEditing) { selection in
            NavigationStack {
                ImportChapterEditor(number: selection.number, name: selection.name) { number, name in
                    model.editChapter(index: selection.index, number: number, name: name)
                    chapterEditing = nil; acknowledged = false
                }
            }
        }
        .onDisappear { model.cancel() }
        .interactiveDismissDisabled(model.working)
    }
    private var sourceBody: some View {
        Form {
            Section("词书资料") {
                TextField("词书名称", text: $model.name)
                Button { chooseFile = true } label: { Label("从“文件”选择资料", systemImage: "doc.badge.plus") }.disabled(model.working)
                Picker("文本格式", selection: $model.fileExtension) {
                    Text("普通文本 / PDF 提取文本").tag("txt")
                    Text("CSV").tag("csv"); Text("JSON").tag("json")
                    if model.fileExtension == "pdf" { Text("PDF").tag("pdf") }
                }
                TextEditor(text: $model.sourceText).font(.body).frame(minHeight: 240)
                    .overlay(alignment: .topLeading) {
                        if model.sourceText.isEmpty { Text("也可以直接粘贴词表、Lesson 或教材资料。").foregroundStyle(.tertiary).padding(6).allowsHitTesting(false) }
                    }
                Text("\(model.sourceText.count) 字符").font(.caption).foregroundStyle(.secondary)
            }.disabled(model.working)
            Section {
                Toggle("使用 AI 整理资料", isOn: $model.useAI).disabled(model.working)
                Text(model.useAI ? "点击下方按钮后，提取的文本会分段发送给 DeepSeek 深度模式。AI 结果必须先经过本地校验和你的预览确认。" : "本地解析不联网。TXT 每行一个英文词，或用 Tab 分隔英文与中文；Lesson 1 这样的行作为章节。CSV 需要 word 表头，JSON 使用标准词书结构。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if model.working {
                Section { HStack { ProgressView(); Text(model.progressText) }; Button("取消处理") { model.cancel() } }
            } else {
                Section { Button("识别并显示预览") { acknowledged = false; model.analyse(store: store) }.disabled(model.sourceText.isEmpty) }
            }
            if let error = model.errorMessage { Section { Text(error).foregroundStyle(.red) } }
        }
    }
    private func previewBody(_ preview: ImportPreview) -> some View {
        List {
            Section("导入概要") {
                TextField("词书名称", text: Binding(get: { model.preview?.draft.name ?? "" }, set: { model.rename($0) }))
                LabeledContent("Lesson 数量", value: "\(preview.draft.chapters.count)")
                LabeledContent("待导入单词", value: "\(preview.wordCount)")
                LabeledContent("已去除的同课重复", value: "\(preview.duplicateCount)")
                LabeledContent("识别或校验失败", value: "\(preview.failedCount)")
            }
            if !preview.issues.isEmpty {
                Section("需要核对 · 包含初次识别报告") {
                    ForEach(preview.issues) { issue in
                        VStack(alignment: .leading, spacing: 5) {
                            if let word = issue.word { Text(word).font(.headline) }
                            Text((issue.lessonNumber.map { "Lesson \($0)：" } ?? "") + issue.message)
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            ForEach(Array(preview.draft.chapters.enumerated()), id: \.offset) { chapterIndex, chapter in
                Section(chapter.lessonName ?? "Lesson \(chapter.lessonNumber)") {
                    Menu("管理这一课") {
                        Button("修改 Lesson 编号与名称") {
                            chapterEditing = ImportChapterSelection(index: chapterIndex, number: chapter.lessonNumber,
                                                                    name: chapter.lessonName ?? "Lesson \(chapter.lessonNumber)")
                        }
                        Button("从预览删除这一课", role: .destructive) { model.removeChapter(index: chapterIndex); acknowledged = false }
                    }
                    ForEach(Array(chapter.words.enumerated()), id: \.offset) { wordIndex, word in
                        Button {
                            editing = ImportWordSelection(chapter: chapterIndex, word: wordIndex, details: word)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(word.word).font(.headline)
                                    Text(word.coreMeaning.isEmpty ? "点击补全释义" : word.coreMeaning).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: "pencil").font(.caption)
                            }
                        }
                        .swipeActions { Button("删除", role: .destructive) { model.removeWord(chapter: chapterIndex, word: wordIndex); acknowledged = false } }
                        .contextMenu { Button("删除词条", role: .destructive) { model.removeWord(chapter: chapterIndex, word: wordIndex); acknowledged = false } }
                    }
                }
            }
            Section {
                Toggle("我已检查预览与问题词条", isOn: $acknowledged)
                Button("确认导入 \(preview.wordCount) 个词条") {
                    if store.importBook(preview) { dismiss() }
                    else { model.errorMessage = store.errorMessage; store.errorMessage = nil }
                }.disabled(!preview.canImport || !acknowledged)
                Button("返回修改原始资料") { model.backToSource(); acknowledged = false }
            }
            if let error = model.errorMessage { Section { Text(error).foregroundStyle(.red) } }
        }
    }
}
@MainActor
private struct ImportChapterEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var number: Int
    @State var name: String
    var onSave: (Int, String) -> Void
    var body: some View {
        Form {
            TextField("Lesson 编号", value: $number, format: .number).keyboardType(.numberPad)
            TextField("Lesson 名称", text: $name)
            Text("编号相同的章节会合并，并重新检查同课重复词条。").font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("修改 Lesson")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { onSave(number, name) }.disabled(number < 1) }
            }
    }
}
@MainActor
private struct ImportWordEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var details: LexicalDetails
    var onSave: (LexicalDetails) -> Void
    var body: some View {
        LexicalEditorForm(details: $details).navigationTitle("修改预览词条")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存修改") { onSave(details) }.disabled(TextKey.normalize(details.word).isEmpty) }
            }
    }
}
