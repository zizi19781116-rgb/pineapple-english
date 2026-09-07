import SwiftUI
import PineappleCore

@MainActor
struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    var onNavigate: (AppRoute) -> Void
    @State private var session: SessionRequest?
    private var today: StudyStatistics { StatisticsService.calculate(store.snapshot, period: .day) }
    private var mainBook: Book? { store.snapshot.books.first { $0.id == store.snapshot.settings.mainBookID } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Date.now, format: .dateTime.month(.wide).day().weekday(.wide)).font(.subheadline).foregroundStyle(.secondary)
                    Text("让今天的学习，\n成为明天的熟悉。").font(.system(.largeTitle, design: .rounded, weight: .semibold)).lineSpacing(4)
                }.padding(.top, 10)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 14) {
                    MetricTile(title: "今日学习", value: StatisticsService.durationText(today.seconds), icon: "clock")
                    MetricTile(title: "今日新词", value: "\(today.newWords)", icon: "sparkle")
                    MetricTile(title: "今日复习", value: "\(today.reviewedWords)", icon: "arrow.clockwise")
                    MetricTile(title: "今日正确率", value: today.accuracy.map { String(format: "%.0f%%", $0 * 100) } ?? "—", icon: "checkmark.circle")
                    MetricTile(title: "待复习", value: "\(store.snapshot.dueWords().count)", icon: "calendar")
                    MetricTile(title: "连续学习", value: "\(StatisticsService.streak(store.snapshot)) 天", icon: "sun.max")
                }
                if let book = mainBook { bookProgress(book) }
                else {
                    Surface("从第一本词书开始") {
                        Text("导入自己的词表或教材资料。学习记录只保存在这台设备，随时可以迁出备份。")
                            .foregroundStyle(.secondary).lineSpacing(5)
                        Button("导入词书") { onNavigate(.books) }.buttonStyle(.borderedProminent)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                    action("继续学习", subtitle: "按主词书逐课学习", icon: "play.fill", scope: .newWords)
                    action("开始复习", subtitle: "优先复习到期单词", icon: "arrow.clockwise", scope: .due)
                    action("错题复习", subtitle: "理解上一次的错误", icon: "xmark.circle", scope: .mistakes)
                    action("困难词复习", subtitle: "巩固长期不稳定的记忆", icon: "leaf", scope: .weak)
                }
                if let warning = store.backupWarning { InlineNotice(text: warning) }
            }.padding(24).frame(maxWidth: 1160).frame(maxWidth: .infinity)
        }
        .sheet(item: $session) { request in NavigationStack { StudySessionView(scope: request.scope) }.environmentObject(store) }
    }
    private func bookProgress(_ book: Book) -> some View {
        let words = store.snapshot.words(in: book.id)
        let learned = words.filter { $0.progress.totalAnswers > 0 }.count
        let chapters = store.snapshot.chapters(in: book.id)
        let current = chapters.first { chapter in words.contains { $0.chapterID == chapter.id && $0.progress.totalAnswers == 0 } }
        return Surface("当前主词书") {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(book.name).font(.title2.bold())
                    Text(current?.lessonName ?? "已学完所有新词，继续复习吧").foregroundStyle(.secondary)
                }
                Spacer()
                Button("查看词书") { onNavigate(.books) }.buttonStyle(.bordered)
            }
            ProgressView(value: Double(learned), total: Double(max(1, words.count)))
            Text("已学习 \(learned) / \(words.count)").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func action(_ title: String, subtitle: String, icon: String, scope: StudyScope) -> some View {
        Button { session = SessionRequest(scope: scope) } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(); Image(systemName: "chevron.right").font(.caption)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }
}
