import Foundation

/// Measuring modes. Each one is backed by a single sensor.
enum MeasureMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case distance, range, box, near, level

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distance: "Distance"
        case .range: "Range"
        case .box: "Box"
        case .near: "Near"
        case .level: "Level"
        }
    }

    var systemImage: String {
        switch self {
        case .distance: "ruler"
        case .range: "scope"
        case .box: "shippingbox"
        case .near: "faceid"
        case .level: "level"
        }
    }

    var sensor: String {
        switch self {
        case .distance, .range, .box: "LiDAR"
        case .near: "TrueDepth"
        case .level: "Motion"
        }
    }

    var usesLiDAR: Bool { sensor == "LiDAR" }
}

enum UnitSystem: String, Codable, CaseIterable, Identifiable, Sendable {
    case metric, imperial

    var id: String { rawValue }
    var title: String { self == .metric ? "Metric (cm, m)" : "Imperial (in, ft)" }
}

/// One saved result.
/// `values` holds meters for distance, range and near; [length, width, height] in meters for a box;
/// and degrees for level.
struct MeasurementRecord: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var date: Date = Date()
    var mode: MeasureMode
    var values: [Double]
}

enum MeasureFormat {
    static func length(_ meters: Double, units: UnitSystem) -> String {
        switch units {
        case .metric:
            if meters < 1 { return String(format: "%.1f cm", meters * 100) }
            return String(format: "%.2f m", meters)
        case .imperial:
            let inches = meters / 0.0254
            if inches < 36 { return String(format: "%.1f in", inches) }
            let feet = Int(inches / 12)
            return String(format: "%d ft %.1f in", feet, inches - Double(feet) * 12)
        }
    }

    /// "40.0 × 30.0 × 25.0 cm" — all three sides in the same unit so they compare at a glance.
    static func box(_ dims: [Double], units: UnitSystem) -> String {
        guard dims.count == 3 else { return "—" }
        switch units {
        case .metric:
            return String(format: "%.1f × %.1f × %.1f cm", dims[0] * 100, dims[1] * 100, dims[2] * 100)
        case .imperial:
            let i = dims.map { $0 / 0.0254 }
            return String(format: "%.1f × %.1f × %.1f in", i[0], i[1], i[2])
        }
    }

    static func angle(_ degrees: Double) -> String { String(format: "%.1f°", degrees) }

    static func summary(_ record: MeasurementRecord, units: UnitSystem) -> String {
        switch record.mode {
        case .box: box(record.values, units: units)
        case .level: angle(record.values.first ?? 0)
        default: length(record.values.first ?? 0, units: units)
        }
    }

    /// Sentence Siri reads back.
    static func spoken(_ record: MeasurementRecord, units: UnitSystem) -> String {
        let value = summary(record, units: units)
        switch record.mode {
        case .box: return "Your last box measured \(value)."
        case .level: return "Your last level reading was \(value)."
        default: return "Your last \(record.mode.title.lowercased()) measurement was \(value)."
        }
    }
}

enum DimensionalWeight {
    /// Courier dimensional weight in kilograms: L × W × H in cm³ divided by the courier's divisor.
    static func kilograms(_ dims: [Double], divisor: Double) -> Double {
        guard dims.count == 3, divisor > 0 else { return 0 }
        return dims.reduce(1) { $0 * $1 * 100 } / divisor
    }

    static func liters(_ dims: [Double]) -> Double {
        guard dims.count == 3 else { return 0 }
        return dims.reduce(1, *) * 1000
    }
}
