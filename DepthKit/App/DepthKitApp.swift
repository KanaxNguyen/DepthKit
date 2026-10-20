import SwiftUI

@main
struct DepthKitApp: App {
    @State private var router = AppRouter()
    @State private var history = HistoryModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(history)
                .onOpenURL { router.handle(url: $0) }
                .onReceive(NotificationCenter.default.publisher(for: .depthKitOpenMode)) { _ in
                    router.consumePendingMode()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    router.consumePendingMode()
                    history.reload()
                }
        }
    }
}
