import SwiftUI
import PineappleCore

private struct EditableExample: Identifiable {
    let id = UUID()
    var sentence: ExampleSentence
}

private enum ExampleTextField {
    case english, chinese
}

@MainActor
struct LexicalEditorForm: View {
    @Binding var details: LexicalDetails
    @State private var exampleRows: [EditableExample]

    init(details: Binding<LexicalDetails>) {
        _details = details
        _exampleRows = State(initialValue: (details.wrappedValue.examples ?? []).map { EditableExample(sentence: $0) })
    }

    var body: some View {
        Form {
            Section("基础资料") {
                TextField("英文单词或词组", text: $details.word).textInputAutocapitalization(.never).autocorrectionDisabled()
                optionalField("英式音标", keyPath: \.ipa)
                linesField("中文释义（每行一个）", keyPath: \.meanings)
                linesField("词性（每行一个）", keyPath: \.part_of_speech)
                optionalField("英文释义", keyPath: \.english_definition)
            }
            Section("例句") {
                ForEach(exampleRows) { row in
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("英文例句", text: exampleText(row.id, field: .english), axis: .vertical)
                            .textInputAutocapitalization(.sentences)
                        TextField("中文翻译（可空）", text: exampleText(row.id, field: .chinese), axis: .vertical)
                        Button("删除这条例句", role: .destructive) { removeExample(row.id) }.font(.caption)
                    }.padding(.vertical, 6)
                }
                Button("添加例句") {
                    exampleRows.append(EditableExample(sentence: ExampleSentence(english: "")))
                    writeExamples()
                }
            }
            Section("扩展资料 · 每行一项，可以留空") {
                linesField("常用义", keyPath: \.common_meanings)
                linesField("常用词组", keyPath: \.phrases)
                linesField("词形变化", keyPath: \.inflections)
                linesField("派生词", keyPath: \.derivatives)
                linesField("词根词缀", keyPath: \.roots)
                linesField("近义词", keyPath: \.synonyms)
                linesField("反义词", keyPath: \.antonyms)
            }
        }
        .onAppear { synchronizeExamples() }
        .onChange(of: details.examples) { _, _ in synchronizeExamples() }
    }
    private func exampleText(_ id: UUID, field: ExampleTextField) -> Binding<String> {
        Binding(get: {
            guard let row = exampleRows.first(where: { $0.id == id }) else { return "" }
            switch field {
            case .english: return row.sentence.english
            case .chinese: return row.sentence.chinese ?? ""
            }
        }, set: { text in
            // Resolve the current position for every edit; deleted rows no longer accept writes.
            guard let index = exampleRows.firstIndex(where: { $0.id == id }) else { return }
            switch field {
            case .english: exampleRows[index].sentence.english = text
            case .chinese: exampleRows[index].sentence.chinese = text.isEmpty ? nil : text
            }
            writeExamples()
        })
    }
    private func removeExample(_ id: UUID) {
        guard exampleRows.contains(where: { $0.id == id }) else { return }
        exampleRows.removeAll { $0.id == id }
        writeExamples()
    }
    private func writeExamples() {
        details.examples = exampleRows.map(\.sentence)
    }
    private func synchronizeExamples() {
        let incoming = details.examples ?? []
        // Parent data can arrive after onAppear; our own writes must retain row identities.
        guard incoming != exampleRows.map(\.sentence) else { return }
        exampleRows = incoming.map { EditableExample(sentence: $0) }
    }
    private func optionalField(_ title: String, keyPath: WritableKeyPath<LexicalDetails, String?>) -> some View {
        TextField(title, text: Binding(get: { details[keyPath: keyPath] ?? "" }, set: { details[keyPath: keyPath] = $0.isEmpty ? nil : $0 }), axis: .vertical)
    }
    private func linesField(_ title: String, keyPath: WritableKeyPath<LexicalDetails, [String]?>) -> some View {
        TextField(title, text: Binding(get: { (details[keyPath: keyPath] ?? []).joined(separator: "\n") }, set: {
            details[keyPath: keyPath] = $0.components(separatedBy: "\n")
        }), axis: .vertical).lineLimit(1...6)
    }
}

@MainActor
struct WordEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let wordID: UUID
    @State private var details = LexicalDetails(word: "")
    @State private var loaded = false
    var body: some View {
        LexicalEditorForm(details: $details).navigationTitle("编辑词条")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if store.editWord(wordID, change: { $0.details = details }) { dismiss() }
                    }.disabled(TextKey.normalize(details.word).isEmpty)
                }
            }
            .onAppear {
                if !loaded, let word = store.snapshot.word(wordID) { details = word.details; loaded = true }
            }
    }
}
