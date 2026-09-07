import SwiftUI
import PineappleCore

@MainActor
struct StudyHubView: View {
    @EnvironmentObject private var store: AppStore
    var scope: StudyScope
    @State private var session: SessionRequest?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(scope == .due ? "给记忆一次及时的回应。" : "按自己的节奏，学会每一个词。")
                    .font(.system(.title, design: .rounded, weight: .semibold))
                Surface(scope == .due ? "本次复习" : "今日学习计划") {
                    if scope == .due {
                        Text("\(store.snapshot.dueWords().count) 个单词已到复习时间").font(.title2)
                        Text("根据回答表现调整间隔。提前练习不会直接跳过复习阶段。")
                            .foregroundStyle(.secondary)
                    } else {
                        let today = StatisticsService.calculate(store.snapshot, period: .day)
                        Text("\(today.newWords) / \(store.snapshot.settings.dailyNewGoal) 个新词").font(.title2)
                        ProgressView(value: Double(min(today.newWords, store.snapshot.settings.dailyNewGoal)),
                                     total: Double(store.snapshot.settings.dailyNewGoal))
                        Text("跟随设置中的主词书逐课推进。达到目标后，仍可到词书页面选择整课练习。")
                            .foregroundStyle(.secondary)
                    }
                    Button("开始\(scope == .due ? "复习" : "学习")") { session = SessionRequest(scope: scope) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(store.snapshot.words.isEmpty)
                }
                if scope == .due {
                    let upcoming = store.snapshot.words.filter { ($0.progress.nextReviewDate ?? .distantPast) > Date() }
                        .sorted { ($0.progress.nextReviewDate ?? .distantFuture) < ($1.progress.nextReviewDate ?? .distantFuture) }
                    Surface("接下来的复习") {
                        if upcoming.isEmpty { Text("学习后的单词会在这里显示下一次复习时间。").foregroundStyle(.secondary) }
                        ForEach(Array(upcoming.prefix(12))) { word in
                            NavigationLink(value: WordDestination(id: word.id)) {
                                HStack { Text(word.word); Spacer(); if let date = word.progress.nextReviewDate { Text(date, style: .relative).foregroundStyle(.secondary) } }
                            }
                        }
                    }
                }
                InlineNotice(text: "答错的词会在本轮末尾再练一次。四选一不足 4 个不同释义时，会使用有提示的拼写题。")
            }.padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
        .sheet(item: $session) { request in NavigationStack { StudySessionView(scope: request.scope) }.environmentObject(store) }
    }
}
