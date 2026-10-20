import CoreImage
import Foundation
import UIKit

/// Saves paired RGB + LiDAR samples for training or evaluating depth models.
/// Each sample is a folder under Documents/Captures (visible in the Files app):
///   rgb.jpg          camera image, sensor orientation (landscape)
///   depth.f32        Float32 little-endian, meters, row-major, depthWidth × depthHeight
///   confidence.u8    UInt8 per pixel: 0 low, 1 medium, 2 high
///   depth_preview.png  color-coded depth for a quick look
///   meta.json        sizes, intrinsics, camera pose, device, mode
struct DatasetSample: Codable, Equatable {
    var timestamp: Date
    var device: String
    var mode: String
    var imageWidth: Int
    var imageHeight: Int
    var depthWidth: Int
    var depthHeight: Int
    /// 3×3 pinhole intrinsics at RGB resolution, column-major (fx, 0, 0, 0, fy, 0, cx, cy, 1).
    var intrinsics: [Float]
    /// 4×4 camera-to-world transform, column-major (ARKit convention: camera looks along -Z).
    var cameraToWorld: [Float]
    var floorY: Float?
    var depthFormat = "float32 little-endian meters, row-major"
    var confidenceFormat = "uint8 0=low 1=medium 2=high"
}

enum DatasetWriter {
    static var defaultRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Captures")
    }

    @discardableResult
    static func save(sample: DatasetSample, rgbJPEG: Data?, depth: [Float], confidence: [UInt8]?,
                     preview: CGImage?, root: URL = defaultRoot) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let folder = root.appendingPathComponent("\(formatter.string(from: sample.timestamp))-\(sample.mode)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(sample).write(to: folder.appendingPathComponent("meta.json"))
        try depth.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: folder.appendingPathComponent("depth.f32"))
        if let confidence { try Data(confidence).write(to: folder.appendingPathComponent("confidence.u8")) }
        if let rgbJPEG { try rgbJPEG.write(to: folder.appendingPathComponent("rgb.jpg")) }
        if let preview, let png = UIImage(cgImage: preview).pngData() {
            try png.write(to: folder.appendingPathComponent("depth_preview.png"))
        }
        return folder
    }

    static func jpeg(from pixelBuffer: CVPixelBuffer) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        return CIContext().jpegRepresentation(of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.9])
    }

    static func summary(root: URL = defaultRoot) -> (count: Int, bytes: Int64) {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return (0, 0) }
        var bytes: Int64 = 0
        if let files = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in files {
                bytes += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return (folders.filter { $0.hasDirectoryPath }.count, bytes)
    }

    static func deleteAll(root: URL = defaultRoot) {
        try? FileManager.default.removeItem(at: root)
    }

    static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
