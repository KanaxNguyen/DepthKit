import Foundation
import simd

/// A grayscale image, row-major, values 0…255.
struct GrayImage {
    let width: Int
    let height: Int
    var pixels: [Float]

    func at(_ x: Int, _ y: Int) -> Float { pixels[y * width + x] }

    /// Bilinear sample; nil outside the image.
    func sample(_ x: Double, _ y: Double) -> Float? {
        guard x >= 0, y >= 0, x <= Double(width - 1), y <= Double(height - 1) else { return nil }
        let x0 = min(Int(x), width - 2), y0 = min(Int(y), height - 2)
        let fx = Float(x - Double(x0)), fy = Float(y - Double(y0))
        let top = at(x0, y0) * (1 - fx) + at(x0 + 1, y0) * fx
        let bottom = at(x0, y0 + 1) * (1 - fx) + at(x0 + 1, y0 + 1) * fx
        return top * (1 - fy) + bottom * fy
    }
}

/// One camera view: image, pinhole intrinsics at the image's resolution, and pose, in ARKit conventions
/// (camera looks along −Z, +Y up, image rows grow downward).
struct CameraView {
    var image: GrayImage
    var intrinsics: simd_double3x3
    var cameraToWorld: simd_double4x4

    var center: SIMD3<Double> {
        let c = cameraToWorld.columns.3
        return SIMD3(c.x, c.y, c.z)
    }

    /// Unit ray through a pixel, in world coordinates.
    func ray(through pixel: SIMD2<Double>) -> SIMD3<Double> {
        let k = intrinsics
        let d = SIMD4((pixel.x - k[2][0]) / k[0][0], -(pixel.y - k[2][1]) / k[1][1], -1, 0)
        let w = cameraToWorld * d
        return simd_normalize(SIMD3(w.x, w.y, w.z))
    }

    /// Pixel where a world point appears, or nil if it is behind the camera.
    func project(_ point: SIMD3<Double>) -> SIMD2<Double>? {
        let p = cameraToWorld.inverse * SIMD4(point, 1)
        guard p.z < -1e-6 else { return nil }
        let k = intrinsics
        return SIMD2(k[0][0] * p.x / -p.z + k[2][0], -k[1][1] * p.y / -p.z + k[2][1])
    }
}

/// Distance to the point under a pixel from two views with known poses (motion stereo).
///
/// The phone's own two cameras are only ~1 cm apart, so their disparity at 4 m is a pixel or two.
/// Sliding the phone 15–25 cm between two views (poses from ARKit's visual-inertial tracking) gives
/// a baseline 15–25× wider. Instead of rectifying, this sweeps candidate distances along the reference
/// pixel's ray, projects each into the second view, and keeps the distance whose image patch matches best
/// (normalized cross-correlation), refined to sub-sample precision.
enum Triangulation {
    struct Options {
        var patchRadius = 7
        var minDistance = 0.3
        var maxDistance = 25.0
        /// Samples spaced evenly in inverse distance, i.e. evenly in disparity.
        var steps = 800
        var minScore: Float = 0.8
        /// The best match must beat any other match farther than `uniquenessRadius` px away by this much,
        /// so repeating textures (tiles, blinds) are rejected instead of matched to the wrong copy.
        var minUniqueness: Float = 0.05
        var uniquenessRadius = 8.0
        /// Minimum variance of the reference patch (gray levels²): flat walls can't be matched.
        var minTexture: Float = 20
    }

    struct Match: Equatable {
        var distance: Double
        var score: Float
        var secondScore: Float
        var pixel: SIMD2<Double>
    }

    enum Failure: Error, Equatable {
        case noTexture, outOfView, noMatch, ambiguous
    }

    static func distance(from reference: CameraView, to target: CameraView, at pixel: SIMD2<Double>,
                         options: Options = Options()) -> Result<Match, Failure> {
        let r = options.patchRadius
        guard let template = patch(reference.image, at: pixel, radius: r) else { return .failure(.outOfView) }
        guard variance(template) >= options.minTexture else { return .failure(.noTexture) }

        let origin = reference.center
        let direction = reference.ray(through: pixel)
        let invNear = 1 / options.minDistance, invFar = 1 / options.maxDistance
        var scores = [Float](repeating: -.infinity, count: options.steps)
        var pixels = [SIMD2<Double>?](repeating: nil, count: options.steps)

        for i in 0..<options.steps {
            let inverse = invFar + (invNear - invFar) * Double(i) / Double(options.steps - 1)
            guard let p = target.project(origin + direction / inverse),
                  let candidate = patch(target.image, at: p, radius: r) else { continue }
            scores[i] = ncc(template, candidate)
            pixels[i] = p
        }

        guard let best = scores.indices.max(by: { scores[$0] < scores[$1] }), let bestPixel = pixels[best],
              scores[best].isFinite else { return .failure(.outOfView) }
        guard scores[best] >= options.minScore else { return .failure(.noMatch) }

        let second = scores.indices
            .filter { i in pixels[i].map { simd_distance($0, bestPixel) > options.uniquenessRadius } ?? false }
            .map { scores[$0] }.max() ?? -1
        guard scores[best] - second >= options.minUniqueness else { return .failure(.ambiguous) }

        // Parabola through the best score and its neighbours, in inverse-distance steps.
        var index = Double(best)
        if best > 0, best < options.steps - 1, scores[best - 1].isFinite, scores[best + 1].isFinite {
            let a = Double(scores[best - 1]), b = Double(scores[best]), c = Double(scores[best + 1])
            let denominator = a - 2 * b + c
            if denominator < 0 { index += max(-0.5, min(0.5, 0.5 * (a - c) / denominator)) }
        }
        let inverse = invFar + (invNear - invFar) * index / Double(options.steps - 1)
        return .success(Match(distance: 1 / inverse, score: scores[best], secondScore: second, pixel: bestPixel))
    }

    /// Square patch around a (sub-pixel) center, bilinearly sampled; nil if any of it falls outside.
    static func patch(_ image: GrayImage, at center: SIMD2<Double>, radius: Int) -> [Float]? {
        var values = [Float]()
        values.reserveCapacity((2 * radius + 1) * (2 * radius + 1))
        for dy in -radius...radius {
            for dx in -radius...radius {
                guard let v = image.sample(center.x + Double(dx), center.y + Double(dy)) else { return nil }
                values.append(v)
            }
        }
        return values
    }

    static func ncc(_ a: [Float], _ b: [Float]) -> Float {
        let n = Float(a.count)
        let ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
        var sab: Float = 0, saa: Float = 0, sbb: Float = 0
        for i in a.indices {
            let x = a[i] - ma, y = b[i] - mb
            sab += x * y; saa += x * x; sbb += y * y
        }
        let d = (saa * sbb).squareRoot()
        return d > 1e-6 ? sab / d : -1
    }

    static func variance(_ values: [Float]) -> Float {
        let n = Float(values.count)
        let mean = values.reduce(0, +) / n
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
    }
}
