import CoreGraphics
import Foundation

/// Summary of one depth map, shown in the developer stats panel.
struct DepthStats: Equatable {
    var validFraction: Double
    var highConfidenceFraction: Double
    var minDepth: Double?
    var maxDepth: Double?

    static func compute(depth: [Float], confidence: [UInt8]?) -> DepthStats {
        guard !depth.isEmpty else { return DepthStats(validFraction: 0, highConfidenceFraction: 0) }
        var valid = 0, high = 0
        var lo = Float.infinity, hi = -Float.infinity
        for i in depth.indices {
            let d = depth[i]
            guard d.isFinite, d > 0 else { continue }
            valid += 1
            if let confidence, confidence[i] >= 2 { high += 1 }
            lo = min(lo, d); hi = max(hi, d)
        }
        let n = Double(depth.count)
        return DepthStats(validFraction: Double(valid) / n,
                          highConfidenceFraction: confidence == nil ? Double(valid) / n : Double(high) / n,
                          minDepth: valid > 0 ? Double(lo) : nil,
                          maxDepth: valid > 0 ? Double(hi) : nil)
    }
}

/// Color-coded depth image: near is red, far is blue (Turbo colormap). Low-confidence pixels are dimmed
/// and pixels in `highlight` (the box region) are drawn white.
enum DepthColormap {
    static func rgba(depth: [Float], confidence: [UInt8]?, highlight: Set<Int> = [], maxDepth: Float = 5) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: depth.count * 4)
        for i in depth.indices {
            let d = depth[i]
            guard d.isFinite, d > 0 else { continue }
            var (r, g, b): (Double, Double, Double)
            if highlight.contains(i) {
                (r, g, b) = (1, 1, 1)
            } else {
                (r, g, b) = turbo(Double(min(d, maxDepth) / maxDepth))
                if let confidence, confidence[i] < 2 {
                    let dim = confidence[i] == 0 ? 0.25 : 0.6
                    (r, g, b) = (r * dim, g * dim, b * dim)
                }
            }
            pixels[i * 4] = UInt8(r * 255)
            pixels[i * 4 + 1] = UInt8(g * 255)
            pixels[i * 4 + 2] = UInt8(b * 255)
            pixels[i * 4 + 3] = 255
        }
        return pixels
    }

    static func image(depth: [Float], width: Int, height: Int, confidence: [UInt8]?,
                      highlight: Set<Int> = []) -> CGImage? {
        let pixels = rgba(depth: depth, confidence: confidence, highlight: highlight)
        guard pixels.count == width * height * 4,
              let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Polynomial approximation of Google's Turbo colormap; value 0 (near) is red, 1 (far) is blue.
    /// Uses 5–95 % of the map because both ends of Turbo are nearly black.
    static func turbo(_ value: Double) -> (Double, Double, Double) {
        let t = 0.95 - 0.9 * min(max(value, 0), 1)
        let r = 0.13572138 + t * (4.61539260 + t * (-42.66032258 + t * (132.13108234 + t * (-152.94239396 + t * 59.28637943))))
        let g = 0.09140261 + t * (2.19418839 + t * (4.84296658 + t * (-14.18503333 + t * (4.27729857 + t * 2.82956604))))
        let b = 0.10667330 + t * (12.64194608 + t * (-60.58204836 + t * (110.36276771 + t * (-89.90310912 + t * 27.34824973))))
        return (min(max(r, 0), 1), min(max(g, 0), 1), min(max(b, 0), 1))
    }
}
