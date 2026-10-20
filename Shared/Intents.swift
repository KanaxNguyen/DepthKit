import AppIntents
import Foundation

extension Notification.Name {
    static let depthKitOpenMode = Notification.Name("vn.kanax.depthkit.openMode")
}

enum MeasureModeAppEnum: String, AppEnum {
    case distance, range, box, near, level

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Measuring Mode"

    static var caseDisplayRepresentations: [MeasureModeAppEnum: DisplayRepresentation] = [
        .distance: DisplayRepresentation(title: "Distance", image: .init(systemName: "ruler")),
        .range: DisplayRepresentation(title: "Range", image: .init(systemName: "scope")),
        .box: DisplayRepresentation(title: "Box", image: .init(systemName: "shippingbox")),
        .near: DisplayRepresentation(title: "Near", image: .init(systemName: "faceid")),
        .level: DisplayRepresentation(title: "Level", image: .init(systemName: "level")),
    ]

    var mode: MeasureMode { MeasureMode(rawValue: rawValue) ?? .distance }
}

/// Opens the app in a measuring mode. Used by Siri, Shortcuts, Spotlight and the Control Center control.
struct StartMeasurementIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Measuring"
    static var description = IntentDescription("Opens DepthKit in the measuring mode you choose.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Mode", default: .distance)
    var mode: MeasureModeAppEnum

    init() {}

    init(mode: MeasureModeAppEnum) {
        self.mode = mode
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        SharedSettings.pendingMode = mode.mode
        NotificationCenter.default.post(name: .depthKitOpenMode, object: nil)
        return .result()
    }
}

/// Answers without opening the app.
struct LastMeasurementIntent: AppIntent {
    static var title: LocalizedStringResource = "Last Measurement"
    static var description = IntentDescription("Reads out your most recent DepthKit measurement.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let last = MeasurementStore.shared.latest else {
            return .result(dialog: "You don't have any saved measurements yet.")
        }
        let sentence = MeasureFormat.spoken(last, units: SharedSettings.units)
        return .result(dialog: "\(sentence)")
    }
}
