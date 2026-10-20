import Foundation
import Observation

enum AppTab: Hashable {
    case measure, history, settings
}

/// Which tab and measuring mode are showing. Driven by taps, deep links, Siri and controls.
@Observable
final class AppRouter {
    var tab: AppTab = .measure
    var mode: MeasureMode = .distance

    func open(_ mode: MeasureMode) {
        self.mode = mode
        tab = .measure
    }

    /// depthkit://measure/<mode> and depthkit://history
    func handle(url: URL) {
        guard url.scheme == "depthkit" else { return }
        switch url.host {
        case "measure":
            open(MeasureMode(rawValue: url.lastPathComponent) ?? mode)
        case "history":
            tab = .history
        default:
            break
        }
    }

    func consumePendingMode() {
        guard let pending = SharedSettings.pendingMode else { return }
        SharedSettings.pendingMode = nil
        open(pending)
    }
}
