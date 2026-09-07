import SwiftUI
import PineappleCore

@MainActor
struct WordCollectionView: View {
    @EnvironmentObject private var store: AppStore
    var route: AppRoute
    @State private var session: SessionRequest?
    private var words: [Vocabulary] {
        switch route {
        case .mistakes: return store.snapshot.words.filter(\.isInMistakes)
        case .confusing: return store.snapshot.words.filter { $0.isConfusing(threshold: store.snapshot.settings.confusingWrongThreshold) }
        case .weak: return store.snapshot.words.filter { $0.isWeak() }
        case .favorites: return store.snapshot.words.filter(\.isFavorite)
        default: return []
        }
    }
    private var description: String {
        switch route {
        case .mistakes: return "答错后自动加入。按设置连续答对后移出，也可以在单词详情中手动移出。"
        case .confusing: return "累计错误达到 \(store.snapshot.settings.confusingWrongThreshold) 次时自动标记；手动调整会优先保留。"
        case .weak: return "结合正确率、近期错误和逾期情况识别记忆不稳定的词，也可以手动调整。"
        default: return "收藏适合重要单词和喜欢的表达，与错题和掌握度相互独立。"
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(description).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
                Spacer()
                Button("练习") { session = SessionRequest(scope: .words(words.map(\.id))) }
                    .buttonStyle(.borderedProminent).disabled(words.isEmpty)
            }.padding(20)
            Divider()
            WordShelfView(words: words, emptyMessage: description)
        }
        .sheet(item: $session) { request in NavigationStack { StudySessionView(scope: request.scope) }.environmentObject(store) }
    }
}
