import Foundation
import simd

/// Rectangle on a plane, described by its four corners in order.
struct OrientedRect: Equatable {
    var corners: [SIMD2<Double>]
    var sideA: Double
    var sideB: Double

    var length: Double { max(sideA, sideB) }
    var width: Double { min(sideA, sideB) }
    var area: Double { sideA * sideB }
}

enum Geometry {
    /// Convex hull by Andrew's monotone chain, counter-clockwise, no repeated end point.
    static func convexHull(_ points: [SIMD2<Double>]) -> [SIMD2<Double>] {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard sorted.count > 2 else { return sorted }

        func cross(_ o: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }

        var lower: [SIMD2<Double>] = []
        for p in sorted {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        var upper: [SIMD2<Double>] = []
        for p in sorted.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// Smallest-area rectangle enclosing the points. One side of the optimum always lies on a hull edge,
    /// so trying every edge direction is exact.
    static func minAreaRect(_ points: [SIMD2<Double>]) -> OrientedRect? {
        let hull = convexHull(points)
        guard hull.count >= 3 else { return nil }

        var best: OrientedRect?
        for i in hull.indices {
            let edge = hull[(i + 1) % hull.count] - hull[i]
            let len = simd_length(edge)
            guard len > 1e-12 else { continue }
            let u = edge / len
            let v = SIMD2(-u.y, u.x)

            var minU = Double.infinity, maxU = -Double.infinity
            var minV = Double.infinity, maxV = -Double.infinity
            for p in hull {
                let a = simd_dot(p, u), b = simd_dot(p, v)
                minU = min(minU, a); maxU = max(maxU, a)
                minV = min(minV, b); maxV = max(maxV, b)
            }
            let rect = OrientedRect(
                corners: [minU * u + minV * v, maxU * u + minV * v, maxU * u + maxV * v, minU * u + maxV * v],
                sideA: maxU - minU,
                sideB: maxV - minV
            )
            if best == nil || rect.area < best!.area { best = rect }
        }
        return best
    }

    /// Linear-interpolated percentile, p in 0...1.
    static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let position = min(max(p, 0), 1) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let t = position - Double(lower)
        return sorted[lower] * (1 - t) + sorted[upper] * t
    }

    static func median(_ values: [Double]) -> Double? { percentile(values, 0.5) }
}
