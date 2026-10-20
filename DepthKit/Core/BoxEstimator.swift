import Foundation
import simd

/// A depth map with everything needed to turn pixels into world points.
struct DepthFrame {
    let width: Int
    let height: Int
    /// Meters along the camera's viewing axis, row-major. 0 or non-finite means no data.
    let depth: [Float]
    /// Optional per-pixel confidence: 0 low, 1 medium, 2 high (ARKit's ARConfidenceLevel raw values).
    let confidence: [UInt8]?
    /// Pinhole intrinsics already scaled to this map's resolution.
    let intrinsics: simd_float3x3
    /// ARKit camera transform (camera looks along -Z, +Y up, image rows grow downward).
    let cameraToWorld: simd_float4x4

    func worldPoint(x: Int, y: Int) -> SIMD3<Float>? {
        let d = depth[y * width + x]
        guard d.isFinite, d > 0 else { return nil }
        let fx = intrinsics[0][0], fy = intrinsics[1][1]
        let cx = intrinsics[2][0], cy = intrinsics[2][1]
        let camera = SIMD4<Float>((Float(x) - cx) * d / fx, -(Float(y) - cy) * d / fy, -d, 1)
        let world = cameraToWorld * camera
        return SIMD3(world.x, world.y, world.z)
    }
}

struct BoxEstimate: Equatable {
    var length: Double
    var width: Double
    var height: Double
    /// Footprint corners on the floor as (x, z) world coordinates.
    var footprint: [SIMD2<Double>]
    var floorY: Double

    var dimensions: [Double] { [length, width, height] }

    /// Eight world-space corners: four on the floor, then the four above them.
    var corners: [SIMD3<Float>] {
        let bottom = footprint.map { SIMD3<Float>(Float($0.x), Float(floorY), Float($0.y)) }
        let top = bottom.map { SIMD3<Float>($0.x, $0.y + Float(height), $0.z) }
        return bottom + top
    }

    static let edges: [(Int, Int)] = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)]
}

/// Finds the box under the crosshair: grow a region of above-floor pixels from the image center,
/// take its height from the top surface, and its footprint as the smallest rectangle around the
/// region's floor projection.
enum BoxEstimator {
    struct Options {
        var minHeight: Float = 0.02
        var minConfidence: UInt8 = 2
        var minPoints = 150
        var maxRange: Float = 4
        var seedSearchRadius = 12
    }

    static func estimate(_ frame: DepthFrame, floorY: Float, options: Options = Options()) -> BoxEstimate? {
        let count = frame.width * frame.height
        guard frame.depth.count == count else { return nil }

        // Height above the floor for every usable pixel.
        var heights = [Float](repeating: -.infinity, count: count)
        var points = [SIMD3<Float>](repeating: .zero, count: count)
        for y in 0..<frame.height {
            for x in 0..<frame.width {
                let i = y * frame.width + x
                let d = frame.depth[i]
                guard d.isFinite, d > 0, d < options.maxRange else { continue }
                if let confidence = frame.confidence, confidence[i] < options.minConfidence { continue }
                guard let p = frame.worldPoint(x: x, y: y) else { continue }
                points[i] = p
                heights[i] = p.y - floorY
            }
        }

        guard let seed = findSeed(frame: frame, heights: heights, options: options) else { return nil }
        let region = grow(from: seed, frame: frame, heights: heights, minHeight: options.minHeight)
        guard region.count >= options.minPoints else { return nil }

        let regionHeights = region.map { Double(heights[$0]) }
        guard let boxHeight = Geometry.percentile(regionHeights, 0.97), boxHeight > 0.03 else { return nil }

        let footprint = region.map { SIMD2<Double>(Double(points[$0].x), Double(points[$0].z)) }
        guard let rect = Geometry.minAreaRect(footprint) else { return nil }

        return BoxEstimate(length: rect.length, width: rect.width, height: boxHeight,
                           footprint: rect.corners, floorY: Double(floorY))
    }

    /// Median of several per-frame estimates; corners come from the sample closest to the median volume.
    static func combine(_ samples: [BoxEstimate]) -> BoxEstimate? {
        guard let l = Geometry.median(samples.map(\.length)),
              let w = Geometry.median(samples.map(\.width)),
              let h = Geometry.median(samples.map(\.height)) else { return nil }
        let volume = l * w * h
        guard var best = samples.min(by: { abs($0.length * $0.width * $0.height - volume) < abs($1.length * $1.width * $1.height - volume) }) else { return nil }
        best.length = l
        best.width = w
        best.height = h
        return best
    }

    private static func findSeed(frame: DepthFrame, heights: [Float], options: Options) -> Int? {
        let cx = frame.width / 2, cy = frame.height / 2
        for radius in 0...options.seedSearchRadius {
            for dy in -radius...radius {
                for dx in -radius...radius where max(abs(dx), abs(dy)) == radius {
                    let x = cx + dx, y = cy + dy
                    guard x >= 0, y >= 0, x < frame.width, y < frame.height else { continue }
                    let i = y * frame.width + x
                    if heights[i] > options.minHeight { return i }
                }
            }
        }
        return nil
    }

    /// 4-connected flood fill over above-floor pixels whose depth changes smoothly.
    private static func grow(from seed: Int, frame: DepthFrame, heights: [Float], minHeight: Float) -> [Int] {
        var visited = [Bool](repeating: false, count: heights.count)
        var queue = [seed]
        visited[seed] = true
        var head = 0
        while head < queue.count {
            let i = queue[head]; head += 1
            let x = i % frame.width, y = i / frame.width
            let d = frame.depth[i]
            let jump = 0.03 + 0.02 * d
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                guard nx >= 0, ny >= 0, nx < frame.width, ny < frame.height else { continue }
                let n = ny * frame.width + nx
                guard !visited[n], heights[n] > minHeight, abs(frame.depth[n] - d) < jump else { continue }
                visited[n] = true
                queue.append(n)
            }
        }
        return queue
    }
}
