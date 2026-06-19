import SwiftUI

@main
struct MacWifiCheckerApp: App {
    @State private var appVM = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appVM)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            // ⌘W でウィンドウ閉じを無効化（ターミナル的使い方を想定）
        }
    }
}
