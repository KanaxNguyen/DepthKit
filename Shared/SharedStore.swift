import Foundation

/// Storage shared by the app, its widgets and its App Intents.
enum AppGroup {
    static let identifier = "group.vn.kanax.depthkit"

    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var defaults: UserDefaults { UserDefaults(suiteName: identifier) ?? .standard }
}

/// Saved measurements as a JSON file in the App Group container.
final class MeasurementStore: @unchecked Sendable {
    static let shared = MeasurementStore(directory: AppGroup.containerURL)

    private let fileURL: URL
    private let queue = DispatchQueue(label: "vn.kanax.depthkit.store")

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("measurements.json")
    }

    func load() -> [MeasurementRecord] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            return (try? JSONDecoder().decode([MeasurementRecord].self, from: data)) ?? []
        }
    }

    func save(_ records: [MeasurementRecord]) throws {
        try queue.sync {
            try JSONEncoder().encode(records).write(to: fileURL, options: .atomic)
        }
    }

    var latest: MeasurementRecord? { load().max { $0.date < $1.date } }
}

/// Settings read outside SwiftUI (intents, widgets). Keys match the app's @AppStorage keys.
enum SharedSettings {
    static let unitsKey = "units"
    static let divisorKey = "dimDivisor"
    private static let pendingModeKey = "pendingMode"

    static var units: UnitSystem {
        UnitSystem(rawValue: AppGroup.defaults.string(forKey: unitsKey) ?? "") ?? .metric
    }

    static var dimDivisor: Double {
        let value = AppGroup.defaults.double(forKey: divisorKey)
        return value > 0 ? value : 5000
    }

    /// Mode requested by Siri or a control; the app consumes it when it becomes active.
    static var pendingMode: MeasureMode? {
        get { AppGroup.defaults.string(forKey: pendingModeKey).flatMap(MeasureMode.init(rawValue:)) }
        set { AppGroup.defaults.set(newValue?.rawValue, forKey: pendingModeKey) }
    }
}
