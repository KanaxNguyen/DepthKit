@preconcurrency import AVFoundation
import Foundation
import Observation
import UIKit

/// One-tap multi-sensor capture for depth experiments. With the iPhone on a tripod it takes, in order:
/// 1. A photo from every back camera (ultra-wide, wide, telephoto) with full calibration
///    (intrinsics, extrinsics relative to each other, lens distortion tables).
/// 2. A photo with Apple's stereo (dual-camera disparity) depth.
/// 3. A photo with LiDAR depth from the LiDAR depth camera.
/// Everything is saved to Documents/LabCaptures/<time>-<label>/ in sensor orientation (landscape);
/// image files carry an EXIF orientation flag that analysis code must ignore.
/// Session work runs on `queue`; published state is only changed on the main actor.
@Observable
final class LabCaptureEngine: @unchecked Sendable {
    static var isSupported: Bool {
        AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) != nil
    }

    static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("LabCaptures")
    }

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "vn.kanax.depthkit.lab")
    @ObservationIgnored private var inFlight: PhotoCollector?

    var isCapturing = false
    var steps: [String] = []
    var resultMessage: String?
    var lastResult: LabResult?

    // MARK: Session

    func startPreview() {
        queue.async { [self] in
            do {
                try configure(Self.multiCameraDevice(), depth: false)
                if !session.isRunning { session.startRunning() }
            } catch {
                DispatchQueue.main.async { self.resultMessage = error.localizedDescription }
            }
        }
    }

    func stop() {
        queue.async { [self] in if session.isRunning { session.stopRunning() } }
    }

    // MARK: Capture

    @MainActor
    func capture(label: String, tapeDistance: Double?) async {
        guard !isCapturing else { return }
        isCapturing = true
        steps = []
        resultMessage = nil
        lastResult = nil
        defer { isCapturing = false }
        var stereoMap: DepthArray?
        var lidarMap: DepthArray?
        var photo: UIImage?

        let folder = Self.root.appendingPathComponent(Self.folderName(label: label))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var files: [String: String] = [:]

            steps.append("Back cameras…")
            let multi = try Self.multiCameraDevice()
            try await onQueue { try self.configure(multi, depth: false) }
            try await settle()
            let constituents = try await takePhotos(constituents: multi.constituentDevices)
            for photo in constituents {
                let name = Self.lensName(photo.sourceDeviceType)
                try Self.writeImage(photo, to: folder.appendingPathComponent("\(name).jpg"))
                if let calibration = photo.cameraCalibrationData {
                    try Self.write(CalibrationRecord(calibration), to: folder.appendingPathComponent("\(name)_calibration.json"))
                }
                files[name] = "\(name).jpg"
            }
            steps[steps.count - 1] = "Back cameras: \(constituents.count) photos ✓"

            steps.append("Apple stereo depth…")
            try await onQueue { try self.configure(multi, depth: true) }
            try await settle()
            if let photo = try await takePhotos(constituents: []).first, let depth = photo.depthData {
                try Self.writeImage(photo, to: folder.appendingPathComponent("apple_stereo_rgb.jpg"))
                stereoMap = try Self.writeDepth(depth, name: "apple_stereo", to: folder)
                steps[steps.count - 1] = "Apple stereo depth ✓"
            } else {
                steps[steps.count - 1] = "Apple stereo depth: not delivered"
            }

            steps.append("LiDAR depth…")
            guard let lidar = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) else {
                throw LabError.message("This iPhone has no LiDAR depth camera.")
            }
            try await onQueue { try self.configure(lidar, depth: true) }
            try await settle()
            if let lidarPhoto = try await takePhotos(constituents: []).first, let depth = lidarPhoto.depthData {
                try Self.writeImage(lidarPhoto, to: folder.appendingPathComponent("lidar_rgb.jpg"))
                lidarMap = try Self.writeDepth(depth, name: "lidar", to: folder)
                photo = lidarPhoto.fileDataRepresentation().flatMap(UIImage.init(data:))
                steps[steps.count - 1] = "LiDAR depth ✓"
            } else {
                steps[steps.count - 1] = "LiDAR depth: not delivered"
            }

            let meta = LabMeta(timestamp: Date(), device: DatasetWriter.deviceModel, label: label,
                               tapeDistanceMeters: tapeDistance, images: files)
            try Self.write(meta, to: folder.appendingPathComponent("meta.json"))

            if let lidarMap {
                lastResult = LabResult(photo: photo, lidar: lidarMap, stereo: stereoMap,
                                       brightness: photo.map(Self.brightness) ?? 0.5,
                                       folderName: folder.lastPathComponent)
            }

            // Back to the multi-camera preview.
            try await onQueue { try self.configure(multi, depth: false) }
            resultMessage = lastResult == nil ? "Saved, but no LiDAR depth to compare." : nil
        } catch {
            resultMessage = "Capture failed: \(error.localizedDescription)"
        }
    }

    static func summary() -> Int {
        (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))?
            .filter(\.hasDirectoryPath).count ?? 0
    }

    // MARK: Configuration (session queue)

    private static func multiCameraDevice() throws -> AVCaptureDevice {
        if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) { return triple }
        if let dual = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) { return dual }
        throw LabError.message("This iPhone has no multi-camera back module.")
    }

    private func configure(_ device: AVCaptureDevice, depth: Bool) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        if (session.inputs.first as? AVCaptureDeviceInput)?.device != device {
            session.inputs.forEach(session.removeInput)
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw LabError.message("Can't use \(device.localizedName).") }
            session.addInput(input)
        }
        if !session.outputs.contains(photoOutput) {
            guard session.canAddOutput(photoOutput) else { throw LabError.message("Can't add photo output.") }
            session.addOutput(photoOutput)
        }

        if device.deviceType == .builtInLiDARDepthCamera {
            try Self.selectLiDARFormat(device)
        } else if let wideZoom = device.virtualDeviceSwitchOverVideoZoomFactors.first {
            // Make the wide camera primary so the stereo depth lines up with the 1× image.
            try device.lockForConfiguration()
            device.videoZoomFactor = CGFloat(truncating: wideZoom)
            device.unlockForConfiguration()
        }

        photoOutput.isVirtualDeviceConstituentPhotoDeliveryEnabled =
            !depth && photoOutput.isVirtualDeviceConstituentPhotoDeliverySupported
        photoOutput.isDepthDataDeliveryEnabled = depth && photoOutput.isDepthDataDeliverySupported
    }

    private static func selectLiDARFormat(_ device: AVCaptureDevice) throws {
        let formats = device.formats.filter { !$0.supportedDepthDataFormats.isEmpty }
        guard let format = formats.max(by: {
            $0.formatDescription.dimensions.width < $1.formatDescription.dimensions.width
        }) else { return }
        let depthFormats = format.supportedDepthDataFormats.filter {
            let type = $0.formatDescription.mediaSubType.rawValue
            return type == kCVPixelFormatType_DepthFloat32 || type == kCVPixelFormatType_DepthFloat16
        }
        try device.lockForConfiguration()
        device.activeFormat = format
        if let best = depthFormats.max(by: {
            $0.formatDescription.dimensions.width < $1.formatDescription.dimensions.width
        }) {
            device.activeDepthDataFormat = best
        }
        device.unlockForConfiguration()
    }

    // MARK: Taking photos

    private func takePhotos(constituents: [AVCaptureDevice]) async throws -> [AVCapturePhoto] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                if !constituents.isEmpty {
                    settings.virtualDeviceConstituentPhotoDeliveryEnabledDevices = constituents
                    settings.isCameraCalibrationDataDeliveryEnabled = photoOutput.isCameraCalibrationDataDeliverySupported
                }
                if photoOutput.isDepthDataDeliveryEnabled {
                    settings.isDepthDataDeliveryEnabled = true
                    settings.isDepthDataFiltered = false
                }
                let collector = PhotoCollector { [weak self] result in
                    self?.inFlight = nil
                    continuation.resume(with: result)
                }
                inFlight = collector
                photoOutput.capturePhoto(with: settings, delegate: collector)
            }
        }
    }

    private func onQueue(_ work: @escaping () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try work()
                    if !self.session.isRunning { self.session.startRunning() }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Lets focus and exposure settle after switching cameras.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(600))
    }

    // MARK: Files

    private static func folderName(label: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let clean = label.lowercased().map { $0.isLetter || $0.isNumber || $0 == "." ? $0 : "-" }
        let suffix = String(clean).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return formatter.string(from: Date()) + (suffix.isEmpty ? "" : "-" + suffix)
    }

    static func lensName(_ type: AVCaptureDevice.DeviceType?) -> String {
        switch type {
        case .builtInUltraWideCamera?: "ultrawide"
        case .builtInWideAngleCamera?: "wide"
        case .builtInTelephotoCamera?: "tele"
        default: "camera"
        }
    }

    private static func writeImage(_ photo: AVCapturePhoto, to url: URL) throws {
        guard let data = photo.fileDataRepresentation() else { throw LabError.message("No image data.") }
        try data.write(to: url)
    }

    /// Writes depth as Float32 meters plus its calibration and size, and returns it.
    @discardableResult
    private static func writeDepth(_ depthData: AVDepthData, name: String, to folder: URL) throws -> DepthArray {
        let depth = depthData.depthDataType == kCVPixelFormatType_DepthFloat32
            ? depthData : depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = PixelBuffers.floats(depth.depthDataMap)
        try map.values.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: folder.appendingPathComponent("\(name)_depth.f32"))
        let info = DepthInfo(width: map.width, height: map.height,
                             quality: depthData.depthDataQuality == .high ? "high" : "low",
                             accuracy: depthData.depthDataAccuracy == .absolute ? "absolute" : "relative",
                             calibration: depthData.cameraCalibrationData.map(CalibrationRecord.init))
        try write(info, to: folder.appendingPathComponent("\(name)_depth.json"))
        return DepthArray(width: map.width, height: map.height, values: map.values)
    }

    /// Mean luminance of a 16 × 16 thumbnail, 0 … 1.
    static func brightness(_ image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 0.5 }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return 0.5 }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        return Double(pixels.reduce(0) { $0 + Int($1) }) / Double(side * side * 255)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url)
    }
}

struct DepthArray {
    let width: Int
    let height: Int
    let values: [Float]
}

/// What the Compare screen shows after a capture.
struct LabResult: Identifiable {
    let id = UUID()
    let photo: UIImage?
    let comparison: SensorComparison
    let lidarImage: CGImage?
    let stereoImage: CGImage?
    let folderName: String

    init(photo: UIImage?, lidar: DepthArray, stereo: DepthArray?, brightness: Double, folderName: String) {
        self.photo = photo
        self.folderName = folderName
        comparison = SensorComparison.compute(lidar: lidar.values, lidarSize: (lidar.width, lidar.height),
                                              stereo: stereo?.values, stereoSize: stereo.map { ($0.width, $0.height) },
                                              brightness: brightness)
        lidarImage = DepthColormap.image(depth: lidar.values, width: lidar.width, height: lidar.height, confidence: nil)
        stereoImage = stereo.flatMap {
            DepthColormap.image(depth: $0.values, width: $0.width, height: $0.height, confidence: nil)
        }
    }
}

enum LabError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { m } else { nil } }
}

private final class PhotoCollector: NSObject, AVCapturePhotoCaptureDelegate {
    private var photos: [AVCapturePhoto] = []
    private var firstError: Error?
    private let completion: (Result<[AVCapturePhoto], Error>) -> Void

    init(completion: @escaping (Result<[AVCapturePhoto], Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { firstError = firstError ?? error } else { photos.append(photo) }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        if let error = error ?? firstError, photos.isEmpty {
            completion(.failure(error))
        } else {
            completion(.success(photos))
        }
    }
}

// MARK: - File formats (read by lab/depthlab/io.py)

/// AVCameraCalibrationData as JSON. Matrices are row-major. Extrinsic translation is in millimeters,
/// as Apple reports it; intrinsics are in pixels at `intrinsicReferenceDimensions`.
struct CalibrationRecord: Codable, Equatable {
    var intrinsicMatrix: [[Float]]
    var intrinsicReferenceDimensions: [Double]
    var extrinsicMatrix: [[Float]]
    var pixelSizeMillimeters: Float
    var lensDistortionCenter: [Double]
    var lensDistortionLookupTable: [Float]
    var inverseLensDistortionLookupTable: [Float]

    init(intrinsicMatrix: [[Float]], intrinsicReferenceDimensions: [Double], extrinsicMatrix: [[Float]],
         pixelSizeMillimeters: Float, lensDistortionCenter: [Double], lensDistortionLookupTable: [Float],
         inverseLensDistortionLookupTable: [Float]) {
        self.intrinsicMatrix = intrinsicMatrix
        self.intrinsicReferenceDimensions = intrinsicReferenceDimensions
        self.extrinsicMatrix = extrinsicMatrix
        self.pixelSizeMillimeters = pixelSizeMillimeters
        self.lensDistortionCenter = lensDistortionCenter
        self.lensDistortionLookupTable = lensDistortionLookupTable
        self.inverseLensDistortionLookupTable = inverseLensDistortionLookupTable
    }

    init(_ c: AVCameraCalibrationData) {
        let k = c.intrinsicMatrix
        let e = c.extrinsicMatrix
        self.init(
            intrinsicMatrix: (0..<3).map { r in [k.columns.0[r], k.columns.1[r], k.columns.2[r]] },
            intrinsicReferenceDimensions: [Double(c.intrinsicMatrixReferenceDimensions.width),
                                           Double(c.intrinsicMatrixReferenceDimensions.height)],
            extrinsicMatrix: (0..<3).map { r in [e.columns.0[r], e.columns.1[r], e.columns.2[r], e.columns.3[r]] },
            pixelSizeMillimeters: c.pixelSize,
            lensDistortionCenter: [Double(c.lensDistortionCenter.x), Double(c.lensDistortionCenter.y)],
            lensDistortionLookupTable: Self.floats(c.lensDistortionLookupTable),
            inverseLensDistortionLookupTable: Self.floats(c.inverseLensDistortionLookupTable)
        )
    }

    private static func floats(_ data: Data?) -> [Float] {
        guard let data else { return [] }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}

struct DepthInfo: Codable {
    var width: Int
    var height: Int
    var quality: String
    var accuracy: String
    var calibration: CalibrationRecord?
    var format = "float32 little-endian meters, row-major, sensor orientation"
}

struct LabMeta: Codable {
    var timestamp: Date
    var device: String
    var label: String
    var tapeDistanceMeters: Double?
    var images: [String: String]
    var orientationNote = "All images and depth maps are in sensor orientation; ignore EXIF orientation."
}
