import SwiftUI
import PineappleCore

@MainActor
struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var route: AppRoute? = .home
    @State private var searchPresented = false
    private let timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
    private var current: AppRoute { route ?? .home }
    var body: some View {
        Group {
            if store.ready {
                Group {
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        NavigationSplitView {
                            List(selection: $route) {
                                Section {
                                    ForEach(Array(AppRoute.allCases.prefix(4))) { item in navLabel(item) }
                                } header: { Text("每天一点，长久记得").textCase(nil) }
                                Section("我的词汇") {
                                    ForEach(Array(AppRoute.allCases[4...8])) { item in navLabel(item) }
                                }
                                Section {
                                    ForEach(Array(AppRoute.allCases.suffix(3))) { item in navLabel(item) }
                                }
                            }
                            .listStyle(.sidebar).navigationTitle("菠萝单词")
                            .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 280)
                        } detail: { contentStack }
                        .navigationSplitViewStyle(.balanced)
                    } else { contentStack }
                }.id(store.epoch)
            } else { RecoveryView() }
        }
        .sheet(isPresented: $searchPresented) { NavigationStack { SearchView() }.environmentObject(store) }
        .alert("提示", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .onChange(of: route) { _, _ in store.leaveLearning() }
        .onChange(of: scenePhase) { _, phase in
            store.foreground(phase == .active)
            if phase == .active { store.checkpointIfNeeded() }
        }
        .onReceive(timer) { _ in
            if scenePhase == .active { _ = store.flushTime(); store.checkpointIfNeeded() }
        }
        .task { store.checkpointIfNeeded() }
    }
    private func navLabel(_ item: AppRoute) -> some View {
        Label(item.title, systemImage: item.icon).tag(item).padding(.vertical, 3)
    }
    private var contentStack: some View {
        NavigationStack {
            sectionView.navigationTitle(current.title)
                .navigationBarTitleDisplayMode(.inline)
                .background(Palette.background)
                .toolbar {
                    if UIDevice.current.userInterfaceIdiom != .pad {
                        ToolbarItem(placement: .topBarLeading) {
                            Menu {
                                ForEach(AppRoute.allCases) { item in
                                    Button { route = item } label: { Label(item.title, systemImage: item.icon) }
                                }
                            } label: { Label("导航", systemImage: "line.3.horizontal") }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { searchPresented = true } label: { Label("全局搜索", systemImage: "magnifyingglass") }
                            .keyboardShortcut("f", modifiers: .command)
                    }
                }
                .navigationDestination(for: WordDestination.self) { destination in WordDetailView(wordID: destination.id) }
        }.id(current)
    }
    @ViewBuilder private var sectionView: some View {
        switch current {
        case .home: HomeView(onNavigate: { route = $0 })
        case .study: StudyHubView(scope: .newWords)
        case .books: BooksView()
        case .review: StudyHubView(scope: .due)
        case .mistakes, .confusing, .weak, .favorites: WordCollectionView(route: current)
        case .notes: NotesView()
        case .ai: AIChatView(wordID: nil)
        case .statistics: StatisticsView()
        case .settings: SettingsView()
        }
    }
}
