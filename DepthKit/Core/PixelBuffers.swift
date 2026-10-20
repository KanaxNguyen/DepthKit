import CoreVideo
import Foundation

/// Copies sensor buffers into plain arrays so the math stays independent of ARKit and AVFoundation.
enum PixelBuffers {
    static func floats(_ buffer: CVPixelBuffer) -> (width: Int, height: Int, values: [Float]) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return (width, height, []) }
        var values = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in 0..<width { values[y * width + x] = row[x] }
        }
        return (width, height, values)
    }

    static func bytes(_ buffer: CVPixelBuffer) -> [UInt8] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return [] }
        var values = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width { values[y * width + x] = row[x] }
        }
        return values
    }

    /// Median depth in a square window at the image center, ignoring empty and low-confidence pixels.
    static func centerMedian(depth: [Float], width: Int, height: Int, confidence: [UInt8]? = nil,
                             minConfidence: UInt8 = 1, window: Int = 5) -> Double? {
        let half = window / 2
        var samples: [Double] = []
        for y in (height / 2 - half)...(height / 2 + half) {
            for x in (width / 2 - half)...(width / 2 + half) {
                guard x >= 0, y >= 0, x < width, y < height else { continue }
                let i = y * width + x
                let d = depth[i]
                guard d.isFinite, d > 0 else { continue }
                if let confidence, confidence[i] < minConfidence { continue }
                samples.append(Double(d))
            }
        }
        return Geometry.median(samples)
    }
}
