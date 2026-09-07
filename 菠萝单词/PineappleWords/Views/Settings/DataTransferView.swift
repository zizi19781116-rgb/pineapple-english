import SwiftUI
import UniformTypeIdentifiers
import PineappleCore

@MainActor
struct DataTransferView: View {
    @EnvironmentObject private var store: AppStore
    @State private var exporting = false
    @State private var document: BackupDocument?
    @State private var importing = false
    @State private var preview: BackupPreview?
    @State private var busy = false
    @State private var message = ""
    @State private var localBackups: [URL] = []
    var body: some View {
        Form {
            if store.ready {
                Section("完整迁出") {
                    Text("词书、学习进度、答题记录、笔记、收藏、复习计划、统计、学习时间、AI 对话和设置都会包含在 ZIP 备份中。")
                    Button { export() } label: { Label("生成完整备份", systemImage: "square.and.arrow.up") }.disabled(busy)
                    Text("备份不包含 API Key，文件未加密，请保存在自己的安全位置。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("从备份迁入") {
                Button { importing = true } label: { Label("选择备份文件", systemImage: "square.and.arrow.down") }.disabled(busy)
                Text("先检查完整性与版本，再显示备份预览。确认后完整恢复；当前数据库会保留，并在迁入前生成保护副本。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if busy { Section { HStack { ProgressView(); Text("正在校验和处理数据…") } } }
            if !message.isEmpty { Section { Text(message).textSelection(.enabled) } }
            Section("本机自动保护副本") {
                if localBackups.isEmpty { Text("开始学习后，每天会生成一个本机保护副本。").foregroundStyle(.secondary) }
                ForEach(localBackups, id: \.path) { url in
                    Button { readBackup(url) } label: { Label(url.deletingPathExtension().lastPathComponent, systemImage: "clock.arrow.circlepath") }.disabled(busy)
                }
                Text("这些副本在本机保存。删除 App、遗失或损坏设备后仍需你保存在设备外的备份。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("数据迁出 / 迁入")
            .fileExporter(isPresented: $exporting, document: document, contentType: .zip, defaultFilename: BackupService.fileName()) { result in
                switch result {
                case .success: message = "完整备份已导出。新设备可从此 ZIP 文件恢复，API Key 需要重新填写。"
                case .failure(let error): message = "备份未导出：\(error.localizedDescription)"
                }
                document = nil
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.zip]) { result in
                switch result { case .success(let url): readBackup(url); case .failure(let error): message = error.localizedDescription }
            }
            .sheet(item: $preview) { value in
                NavigationStack {
                    BackupRestorePreviewView(preview: value) {
                        preview = nil; message = "完整数据已恢复。DeepSeek API Key 保留为本机钥匙串内容。"
                        localBackups = store.coordinator?.localBackups() ?? []
                    }
                }.environmentObject(store).interactiveDismissDisabled(busy)
            }
            .onAppear { localBackups = store.coordinator?.localBackups() ?? [] }
    }
    private func export() {
        busy = true; message = ""
        Task {
            defer { busy = false }
            do { document = BackupDocument(data: try await store.makeExport()); exporting = true }
            catch { message = error.localizedDescription }
        }
    }
    private func readBackup(_ url: URL) {
        busy = true; message = ""
        Task {
            defer { busy = false }
            do { preview = try await Task.detached(priority: .userInitiated) { try BackupService.decode(BackupService.readFile(url)) }.value }
            catch { message = "未迁入任何数据：\(error.localizedDescription)" }
        }
    }
}

@MainActor
struct BackupRestorePreviewView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let preview: BackupPreview
    var onRestored: () -> Void
    @State private var confirmed = false
    @State private var busy = false
    @State private var errorMessage: String?
    var body: some View {
        Form {
            Section("备份已通过校验") {
                LabeledContent("备份时间", value: preview.manifest.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("数据库版本", value: "\(preview.manifest.databaseVersion) → 1")
                LabeledContent("词书", value: "\(preview.snapshot.books.count)")
                LabeledContent("单词", value: "\(preview.snapshot.words.count)")
                LabeledContent("答题记录", value: "\(preview.snapshot.answers.count)")
                LabeledContent("笔记", value: "\(preview.snapshot.notes.count)")
                LabeledContent("累计学习", value: StatisticsService.durationText(preview.manifest.studySeconds))
                LabeledContent("API Key", value: "不包含")
            }
            Section("恢复方式") {
                Text("这会将当前学习库完整切换到备份中的状态，不进行混合合并。")
                if store.ready {
                    Text("当前：\(store.snapshot.words.count) 词，\(store.snapshot.answers.count) 条答题记录。迁入前会创建完整保护副本，并保留旧数据库。")
                        .foregroundStyle(.secondary)
                }
                Toggle("我确认恢复这份完整备份", isOn: $confirmed).disabled(busy)
                Button("确认迁入") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do { try await store.restore(preview); onRestored() }
                        catch { errorMessage = error.localizedDescription }
                    }
                }.disabled(!confirmed || busy)
                if busy { HStack { ProgressView(); Text("正在保护当前数据并恢复，请保持 App 打开…") } }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
        }.navigationTitle("备份预览")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
    }
}
