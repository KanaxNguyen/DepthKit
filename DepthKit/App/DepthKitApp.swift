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
                .task {
                    #if DEBUG
                    // `-labDiagnostics`: write what the cameras support to Documents/lab_diagnostics.json (no photos).
                    if ProcessInfo.processInfo.arguments.contains("-labDiagnostics") {
                        let report = await LabCaptureEngine().diagnostics()
                        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            .appendingPathComponent("lab_diagnostics.json")
                        try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url)
                    }
                    #endif
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    router.consumePendingMode()
                    history.reload()
                }
        }
    }
}
