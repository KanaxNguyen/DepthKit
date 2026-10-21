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

    /// Luma (plane 0 of a YCbCr camera image) averaged over `factor` × `factor` blocks.
    static func luma(_ buffer: CVPixelBuffer, factor: Int) -> GrayImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(buffer) >= 1, let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else {
            return nil
        }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0), height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let w = width / factor, h = height / factor
        let scale = 1 / Float(factor * factor)
        var pixels = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for sy in 0..<factor {
                let row = base.advanced(by: (y * factor + sy) * rowBytes).assumingMemoryBound(to: UInt8.self)
                for x in 0..<w {
                    var sum: Float = 0
                    for sx in 0..<factor { sum += Float(row[x * factor + sx]) }
                    pixels[y * w + x] += sum * scale
                }
            }
        }
        return GrayImage(width: w, height: h, pixels: pixels)
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
