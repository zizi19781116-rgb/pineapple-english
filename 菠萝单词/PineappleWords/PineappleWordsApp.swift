import SwiftUI

@main
@MainActor
struct PineappleWordsApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .tint(Color("AccentColor"))
        }
    }
}
