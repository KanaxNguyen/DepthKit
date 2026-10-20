import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Measure", systemImage: "ruler", value: AppTab.measure) {
                MeasureView()
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                HistoryView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
    }
}
