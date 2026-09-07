import SwiftUI

@MainActor
struct RecoveryView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "externaldrive.badge.exclamationmark").font(.system(size: 42)).foregroundStyle(.orange)
                Text("先保护数据，再继续学习。").font(.title.bold())
                Text(store.recoveryMessage ?? "数据库无法读取，原文件仍保留。").lineSpacing(6).textSelection(.enabled)
                NavigationLink { DataTransferView() } label: { Text("选择备份恢复") }.buttonStyle(.borderedProminent)
                Button("解锁设备后重试打开") { store.openDatabase() }.buttonStyle(.bordered)
                Text("如果暂时没有备份，请保留 App。可以在 Mac 的 Xcode 设备管理中下载应用数据容器，原 SQLite 文件及历史数据库均在 Application Support/PineappleWords 中。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth: 740).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background).navigationTitle("菠萝单词 · 数据恢复")
        }
    }
}
