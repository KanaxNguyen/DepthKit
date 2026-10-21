import Foundation

/// A repeated measurement summarized as a value with a 95 % confidence interval.
/// The interval reflects random scatter between readings (hand shake, sensor noise),
/// not systematic bias such as calibration or surface effects.
struct Estimate: Equatable {
    var value: Double
    /// Half-width of the 95 % confidence interval; nil with fewer than two readings.
    var margin: Double?
    /// Readings used after outlier rejection.
    var count: Int
    /// Readings rejected as outliers.
    var rejected: Int = 0

    var low: Double { value - (margin ?? 0) }
    var high: Double { value + (margin ?? 0) }

    func overlaps(_ other: Estimate) -> Bool {
        low <= other.high && other.low <= high
    }
}

enum RobustStats {
    /// Mean of the readings that survive a median ± 3·MAD outlier test, with a Student-t 95 % interval.
    static func estimate(_ samples: [Double]) -> Estimate? {
        let finite = samples.filter(\.isFinite)
        guard let med = Geometry.median(finite) else { return nil }
        guard finite.count > 1 else { return Estimate(value: med, margin: nil, count: 1) }

        // 1.4826 · MAD estimates the standard deviation for normal data. When more than half the readings
        // equal the median, MAD is 0 and would reject every other reading, so fall back to the mean
        // absolute deviation (× 1.2533 for the same scale).
        let deviations = finite.map { abs($0 - med) }
        var scale = 1.4826 * (Geometry.median(deviations) ?? 0)
        if scale < 1e-9 { scale = 1.2533 * deviations.reduce(0, +) / Double(deviations.count) }
        let limit = max(3 * scale, 1e-9)
        let inliers = finite.filter { abs($0 - med) <= limit }
        let n = inliers.count
        let mean = inliers.reduce(0, +) / Double(n)
        guard n > 1 else { return Estimate(value: mean, margin: nil, count: n, rejected: finite.count - n) }
        let variance = inliers.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(n - 1)
        let margin = tCritical95(degreesOfFreedom: n - 1) * (variance / Double(n)).squareRoot()
        return Estimate(value: mean, margin: margin, count: n, rejected: finite.count - n)
    }

    /// Two-sided 95 % Student-t critical values.
    static func tCritical95(degreesOfFreedom df: Int) -> Double {
        let table: [Double] = [12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228,
                               2.201, 2.179, 2.160, 2.145, 2.131, 2.120, 2.110, 2.101, 2.093, 2.086,
                               2.080, 2.074, 2.069, 2.064, 2.060, 2.056, 2.052, 2.048, 2.045, 2.042]
        guard df >= 1 else { return .infinity }
        return df <= table.count ? table[df - 1] : 1.96
    }

    /// Per-pixel median of several aligned depth maps of the same size (NaN where no map has depth).
    static func medianStack(_ maps: [[Float]]) -> [Float] {
        guard let first = maps.first else { return [] }
        if maps.count == 1 { return first }
        var out = [Float](repeating: .nan, count: first.count)
        var column = [Float]()
        column.reserveCapacity(maps.count)
        for i in first.indices {
            column.removeAll(keepingCapacity: true)
            for map in maps where i < map.count {
                let v = map[i]
                if v.isFinite, v > 0 { column.append(v) }
            }
            guard !column.isEmpty else { continue }
            column.sort()
            let mid = column.count / 2
            out[i] = column.count % 2 == 1 ? column[mid] : (column[mid - 1] + column[mid]) / 2
        }
        return out
    }
}

/// The last few seconds of a live reading. Starts over when the reading jumps to a new target.
struct RollingWindow {
    var capacity: Int
    /// A reading this far (as a fraction) from the window's median means the user aimed somewhere else.
    var jumpFraction: Double = 0.08
    private(set) var samples: [Double] = []

    init(capacity: Int) {
        self.capacity = capacity
    }

    mutating func add(_ value: Double?) {
        guard let value, value.isFinite else { return }
        if let med = Geometry.median(samples), med > 0, abs(value - med) / med > jumpFraction {
            samples.removeAll()
        }
        samples.append(value)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    }

    mutating func reset() { samples.removeAll() }

    var estimate: Estimate? { RobustStats.estimate(samples) }
}
