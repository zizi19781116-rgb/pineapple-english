import Foundation

enum AppRoute: String, CaseIterable, Identifiable {
    case home, study, books, review, mistakes, confusing, weak, favorites, notes, ai, statistics, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "首页"; case .study: return "学习"; case .books: return "词书"; case .review: return "复习"
        case .mistakes: return "错题"; case .confusing: return "易错词"; case .weak: return "薄弱词"
        case .favorites: return "收藏"; case .notes: return "笔记"; case .ai: return "AI 问答"
        case .statistics: return "学习统计"; case .settings: return "设置"
        }
    }
    var icon: String {
        switch self {
        case .home: return "square.grid.2x2"; case .study: return "rectangle.and.pencil.and.ellipsis"
        case .books: return "books.vertical"; case .review: return "arrow.clockwise"
        case .mistakes: return "xmark.circle"; case .confusing: return "arrow.left.arrow.right"
        case .weak: return "leaf"; case .favorites: return "bookmark"; case .notes: return "note.text"
        case .ai: return "bubble.left.and.bubble.right"; case .statistics: return "chart.bar.xaxis"; case .settings: return "slider.horizontal.3"
        }
    }
}
enum StudyScope: Equatable {
    case newWords, due, mistakes, confusing, weak, book(UUID), words([UUID])
    var title: String {
        switch self { case .newWords: return "学习新词"; case .due: return "到期复习"; case .mistakes: return "错题复习"
        case .confusing: return "易错词练习"; case .weak: return "薄弱词练习"; case .book: return "词书练习"; case .words: return "单词练习" }
    }
}
struct SessionRequest: Identifiable {
    var id = UUID()
    var scope: StudyScope
}
struct WordDestination: Identifiable, Hashable { var id: UUID }
