import SwiftUI
import Charts
import PineappleCore

@MainActor
struct StatisticsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var period: StatisticsPeriod = .week
    @State private var anchor = Date()
    private var metrics: StudyStatistics { StatisticsService.calculate(store.snapshot, period: period, anchor: anchor) }
    private var annual: [YearStatistics] { StatisticsService.annual(store.snapshot) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("每一点积累，都有记录。").font(.system(.title, design: .rounded, weight: .semibold))
                Picker("时间范围", selection: $period) {
                    ForEach(StatisticsPeriod.allCases) { value in Text(value.title).tag(value) }
                }.pickerStyle(.segmented)
                if period != .all { DatePicker("查看日期所在的\(period.title)", selection: $anchor, in: ...Date(), displayedComponents: .date) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 14) {
                    MetricTile(title: "学习时间", value: StatisticsService.durationText(metrics.seconds), icon: "clock")
                    MetricTile(title: "新学单词", value: "\(metrics.newWords)", icon: "sparkle")
                    MetricTile(title: "复习单词", value: "\(metrics.reviewedWords)", icon: "arrow.clockwise")
                    MetricTile(title: "总答题数", value: "\(metrics.answerCount)", icon: "pencil")
                    MetricTile(title: "正确 / 错误", value: "\(metrics.correctCount) / \(metrics.wrongCount)", icon: "checkmark.circle")
                    MetricTile(title: "正确率", value: metrics.accuracy.map { String(format: "%.1f%%", $0 * 100) } ?? "—", icon: "chart.pie")
                }
                Surface("当前词库状态") {
                    LabeledContent("已掌握", value: "\(store.snapshot.words.filter { $0.progress.masteryLevel.rawValue >= MasteryLevel.mastered.rawValue }.count)")
                    LabeledContent("薄弱词", value: "\(store.snapshot.words.filter { $0.isWeak() }.count)")
                    LabeledContent("易错词", value: "\(store.snapshot.words.filter { $0.isConfusing(threshold: store.snapshot.settings.confusingWrongThreshold) }.count)")
                    Text("这里反映当前状态；上方答题统计按所选时段计算。").font(.caption).foregroundStyle(.secondary)
                }
                Surface("历年学习时间") {
                    if annual.isEmpty { Text("开始学习后，每一年的时间都会永久保留。").foregroundStyle(.secondary) }
                    else {
                        Chart(annual) { year in
                            BarMark(x: .value("年份", String(year.year)), y: .value("学习小时", year.seconds / 3600))
                                .foregroundStyle(Palette.accent)
                        }.frame(height: 220).chartYAxisLabel("小时")
                        ForEach(annual) { year in LabeledContent("\(String(year.year)) 年", value: StatisticsService.durationText(year.seconds)) }
                    }
                    Divider()
                    LabeledContent("累计学习总时间", value: StatisticsService.durationText(StatisticsService.calculate(store.snapshot, period: .all).seconds))
                        .font(.headline)
                }
                InlineNotice(text: "新词按首次答题计数，复习词按非首次答题去重；同一个词可在首次学习后再次复习。正确率按答题次数计算。计时只在学习页面有操作后开始，无操作达到设定时间自动暂停，切换页面或进入后台停止。")
            }.padding(24).frame(maxWidth: 1080).frame(maxWidth: .infinity)
        }
    }
}
