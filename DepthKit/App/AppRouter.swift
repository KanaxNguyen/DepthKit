import Foundation
import Observation

enum AppTab: Hashable {
    case measure, history, settings
}

/// The three tools in the mode switcher. Distance covers every "how far" measurement.
enum MeasureTool: String, CaseIterable, Identifiable {
    case distance, box, level

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distance: "Distance"
        case .box: "Box"
        case .level: "Level"
        }
    }

    var systemImage: String {
        switch self {
        case .distance: "ruler"
        case .box: "shippingbox"
        case .level: "level"
        }
    }
}

enum DistanceMethod: String, CaseIterable, Identifiable {
    /// Between two points picked in the scene (LiDAR).
    case twoPoints
    /// From the iPhone to whatever is under the crosshair (LiDAR or TrueDepth).
    case fromPhone
    /// LiDAR versus the two-camera (stereo) depth, side by side.
    case compare

    var id: String { rawValue }
    var title: String {
        switch self {
        case .twoPoints: "Two Points"
        case .fromPhone: "From iPhone"
        case .compare: "Compare"
        }
    }
}

enum DistanceSensor {
    case lidar, trueDepth
}

/// Which tab and measuring tool are showing. Driven by taps, deep links, Siri and controls.
@Observable
final class AppRouter {
    var tab: AppTab = .measure
    var tool: MeasureTool = .distance
    var distanceMethod: DistanceMethod = .twoPoints
    var distanceSensor: DistanceSensor = ARMeasureEngine.isSupported ? .lidar : .trueDepth

    /// The concrete measuring mode, which is also the kind of record it saves.
    var mode: MeasureMode {
        switch tool {
        case .box: .box
        case .level: .level
        case .distance:
            switch distanceMethod {
            case .twoPoints: .distance
            case .fromPhone, .compare: distanceSensor == .lidar ? .range : .near
            }
        }
    }

    func open(_ mode: MeasureMode) {
        switch mode {
        case .distance:
            tool = .distance; distanceMethod = .twoPoints
        case .range:
            tool = .distance; distanceMethod = .fromPhone; distanceSensor = .lidar
        case .near:
            tool = .distance; distanceMethod = .fromPhone; distanceSensor = .trueDepth
        case .box:
            tool = .box
        case .level:
            tool = .level
        }
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
