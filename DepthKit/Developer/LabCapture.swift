@preconcurrency import AVFoundation
import Foundation
import Observation
import UIKit

/// One-tap multi-sensor capture for depth experiments. Held still, it takes in order:
/// 1. A photo from the wide and ultra-wide cameras (Dual Wide virtual device).
/// 2. A photo with Apple's stereo (dual-camera disparity) depth, wide camera primary.
///    Its calibration (intrinsics, lens distortion) is saved as the wide camera's. On iPhone 15 Pro the
///    ultra-wide's calibration is not available: neither constituent photos nor ultra-wide-primary depth
///    photos deliver it.
/// 3. Photos with LiDAR depth from the LiDAR depth camera.
/// Apple's two-camera depth is Portrait-style: `depthDataAccuracy` is relative and it saturates around 2.5 m.
/// (The Triple Camera's default photo formats have no depth formats, so Dual Wide is used for stereo.)
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

    /// Gyroscope shake level, so each shot waits for a steady hand.
    @ObservationIgnored let motion = MotionMonitor()

    var isCapturing = false
    var steps: [String] = []
    var resultMessage: String?
    var lastResult: LabResult?

    // MARK: Session

    func startPreview() {
        motion.start()
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
        motion.stop()
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
        var stereoCenters: [Double] = []
        var lidarCenters: [Double] = []
        var photo: UIImage?

        let folder = Self.root.appendingPathComponent(Self.folderName(label: label))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var files: [String: String] = [:]

            steps.append("Wide + ultra-wide…")
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
            steps[steps.count - 1] = "Wide + ultra-wide: \(constituents.count) photos ✓"

            let shots = max(1, DevSettings.compareShots)
            var shakes: [Double] = []

            steps.append("Two cameras…")
            try await onQueue { try self.configure(multi, depth: true) }
            try await settle()
            let stereo = try await takeDepthShots(shots, label: "Two cameras")
            shakes += stereo.shakes
            if let first = stereo.photos.first, let depth = first.depthData, let merged = Self.merge(stereo.maps) {
                try Self.writeImage(first, to: folder.appendingPathComponent("apple_stereo_rgb.jpg"))
                try Self.writeDepth(merged, source: depth, name: "apple_stereo", to: folder)
                try Self.writeCalibrationIfMissing(depth.cameraCalibrationData, lens: "wide", in: folder)
                stereoMap = merged
                stereoCenters = stereo.maps.compactMap(Self.center)
                steps[steps.count - 1] = "Two cameras: \(stereo.maps.count) shots ✓"
            } else {
                steps[steps.count - 1] = "Two cameras: no depth delivered"
            }


            steps.append("LiDAR depth…")
            guard let lidar = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) else {
                throw LabError.message("This iPhone has no LiDAR depth camera.")
            }
            try await onQueue { try self.configure(lidar, depth: true) }
            try await settle()
            let lidarShots = try await takeDepthShots(shots, label: "LiDAR")
            shakes += lidarShots.shakes
            if let first = lidarShots.photos.first, let depth = first.depthData, let merged = Self.merge(lidarShots.maps) {
                try Self.writeImage(first, to: folder.appendingPathComponent("lidar_rgb.jpg"))
                try Self.writeDepth(merged, source: depth, name: "lidar", to: folder)
                lidarMap = merged
                lidarCenters = lidarShots.maps.compactMap(Self.center)
                photo = first.fileDataRepresentation().flatMap(UIImage.init(data:))
                steps[steps.count - 1] = "LiDAR: \(lidarShots.maps.count) shots ✓"
            } else {
                steps[steps.count - 1] = "LiDAR: no depth delivered"
            }

            let meanShake = shakes.isEmpty ? nil : shakes.reduce(0, +) / Double(shakes.count)
            let meta = LabMeta(timestamp: Date(), device: DatasetWriter.deviceModel, label: label,
                               tapeDistanceMeters: tapeDistance, images: files, shots: shots,
                               stereoCenterMeters: stereoCenters, lidarCenterMeters: lidarCenters,
                               shakeRadiansPerSecond: shakes)
            try Self.write(meta, to: folder.appendingPathComponent("meta.json"))

            if let lidarMap {
                lastResult = LabResult(photo: photo, lidar: lidarMap, stereo: stereoMap,
                                       lidarCenters: lidarCenters, stereoCenters: stereoCenters, shake: meanShake,
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
        if let dual = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) { return dual }
        if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) { return triple }
        throw LabError.message("This iPhone has no multi-camera back module.")
    }

    private func configure(_ device: AVCaptureDevice, depth: Bool) throws {
        session.beginConfiguration()
        if (session.inputs.first as? AVCaptureDeviceInput)?.device != device {
            session.inputs.forEach(session.removeInput)
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                throw LabError.message("Can't use \(device.localizedName).")
            }
            session.addInput(input)
        }
        if !session.outputs.contains(photoOutput) {
            guard session.canAddOutput(photoOutput) else {
                session.commitConfiguration()
                throw LabError.message("Can't add photo output.")
            }
            session.addOutput(photoOutput)
        }
        // The multi-camera's default photo format has no depth formats, which also turns off depth and
        // calibration delivery. Choose a depth-capable format explicitly; a session preset set in the same
        // transaction would override it, so the preset is only a fallback.
        if device.formats.contains(where: { !$0.supportedDepthDataFormats.isEmpty }) {
            try Self.selectDepthCapableFormat(device)
        } else {
            session.sessionPreset = .photo
        }
        session.commitConfiguration()

        // The photo output reports what it supports only once the new configuration is committed, and
        // constituent-photo delivery and depth delivery exclude each other, so switch one off before the other.
        if depth {
            photoOutput.isVirtualDeviceConstituentPhotoDeliveryEnabled = false
            photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
        } else {
            photoOutput.isDepthDataDeliveryEnabled = false
            photoOutput.isVirtualDeviceConstituentPhotoDeliveryEnabled = photoOutput.isVirtualDeviceConstituentPhotoDeliverySupported
        }

        if device.deviceType != .builtInLiDARDepthCamera, let wideZoom = device.virtualDeviceSwitchOverVideoZoomFactors.first {
            // Make the wide camera primary so the stereo depth lines up with the 1× image.
            try device.lockForConfiguration()
            device.videoZoomFactor = CGFloat(truncating: wideZoom)
            device.unlockForConfiguration()
        }
    }

    /// What this iPhone's photo output supports in each configuration. Takes no photos.
    func diagnostics() async -> [String: String] {
        var report: [String: String] = [:]
        let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera,
                                                   .builtInWideAngleCamera, .builtInLiDARDepthCamera]
        for type in types {
            guard let d = AVCaptureDevice.default(type, for: .video, position: .back) else {
                report["devices.\(type.rawValue)"] = "absent"
                continue
            }
            let withDepth = d.formats.filter { !$0.supportedDepthDataFormats.isEmpty }
            let largest = withDepth.map { $0.formatDescription.dimensions.width }.max() ?? 0
            report["devices.\(type.rawValue)"] = "\(d.formats.count) formats, \(withDepth.count) with depth, largest depth-capable width \(largest)"
        }
        func record(_ prefix: String, _ device: AVCaptureDevice) {
            report["\(prefix).device"] = device.deviceType.rawValue
            report["\(prefix).format"] = "\(device.activeFormat.formatDescription.dimensions.width)x\(device.activeFormat.formatDescription.dimensions.height)"
            report["\(prefix).formatDepthFormats"] = "\(device.activeFormat.supportedDepthDataFormats.count)"
            report["\(prefix).zoom"] = "\(device.videoZoomFactor)"
            report["\(prefix).constituentSupported"] = "\(photoOutput.isVirtualDeviceConstituentPhotoDeliverySupported)"
            report["\(prefix).constituentEnabled"] = "\(photoOutput.isVirtualDeviceConstituentPhotoDeliveryEnabled)"
            report["\(prefix).depthSupported"] = "\(photoOutput.isDepthDataDeliverySupported)"
            report["\(prefix).depthEnabled"] = "\(photoOutput.isDepthDataDeliveryEnabled)"
            report["\(prefix).calibrationSupported"] = "\(photoOutput.isCameraCalibrationDataDeliverySupported)"
        }
        do {
            let multi = try Self.multiCameraDevice()
            try await onQueue { try self.configure(multi, depth: false) }
            try await Task.sleep(for: .milliseconds(500))
            record("multi.photos", multi)
            try await onQueue { try self.configure(multi, depth: true) }
            try await Task.sleep(for: .milliseconds(500))
            record("multi.depth", multi)
            if let dualWide = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
                try await onQueue { try self.configure(dualWide, depth: false) }
                try await Task.sleep(for: .milliseconds(500))
                record("dualWide.photos", dualWide)
                try await onQueue { try self.configure(dualWide, depth: true) }
                try await Task.sleep(for: .milliseconds(500))
                record("dualWide.depth", dualWide)
                // Both at once: Apple only offers per-camera calibration in some combinations.
                try await onQueue {
                    self.photoOutput.isVirtualDeviceConstituentPhotoDeliveryEnabled = true
                    self.photoOutput.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliverySupported
                }
                try await Task.sleep(for: .milliseconds(500))
                record("dualWide.both", dualWide)
            }
            if let lidar = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) {
                try await onQueue { try self.configure(lidar, depth: true) }
                try await Task.sleep(for: .milliseconds(500))
                record("lidar.depth", lidar)
            }
        } catch {
            report["error"] = error.localizedDescription
        }
        stop()
        return report
    }

    private static func selectDepthCapableFormat(_ device: AVCaptureDevice) throws {
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

    private static func writeCalibrationIfMissing(_ calibration: AVCameraCalibrationData?, lens: String, in folder: URL) throws {
        let url = folder.appendingPathComponent("\(lens)_calibration.json")
        guard let calibration, !FileManager.default.fileExists(atPath: url.path) else { return }
        try write(CalibrationRecord(calibration), to: url)
    }

    private static func writeImage(_ photo: AVCapturePhoto, to url: URL) throws {
        guard let data = photo.fileDataRepresentation() else { throw LabError.message("No image data.") }
        try data.write(to: url)
    }

    /// Takes `count` depth photos with the current configuration, each once the hand is steady.
    @MainActor
    private func takeDepthShots(_ count: Int, label: String) async throws
        -> (photos: [AVCapturePhoto], maps: [DepthArray], shakes: [Double]) {
        var photos: [AVCapturePhoto] = []
        var maps: [DepthArray] = []
        var shakes: [Double] = []
        for i in 0..<count {
            steps[steps.count - 1] = "\(label) \(i + 1)/\(count)" + (motion.isSteady ? "…" : " · hold steady…")
            let shake = await motion.waitUntilSteady()
            guard let photo = try await takePhotos(constituents: []).first, let depth = photo.depthData else { continue }
            photos.append(photo)
            maps.append(Self.depthArray(depth))
            shakes.append(shake)
        }
        return (photos, maps, shakes)
    }

    static func depthArray(_ depthData: AVDepthData) -> DepthArray {
        let depth = depthData.depthDataType == kCVPixelFormatType_DepthFloat32
            ? depthData : depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = PixelBuffers.floats(depth.depthDataMap)
        return DepthArray(width: map.width, height: map.height, values: map.values)
    }

    /// Per-pixel median of same-size shots; small hand movements average out.
    static func merge(_ maps: [DepthArray]) -> DepthArray? {
        guard let first = maps.first else { return nil }
        let same = maps.filter { $0.width == first.width && $0.height == first.height }
        return DepthArray(width: first.width, height: first.height, values: RobustStats.medianStack(same.map(\.values)))
    }

    static func center(_ map: DepthArray) -> Double? {
        PixelBuffers.centerMedian(depth: map.values, width: map.width, height: map.height, window: 9)
    }

    /// Writes depth as Float32 meters plus the calibration and quality of the photo it came from.
    private static func writeDepth(_ map: DepthArray, source depthData: AVDepthData, name: String, to folder: URL) throws {
        try map.values.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: folder.appendingPathComponent("\(name)_depth.f32"))
        let info = DepthInfo(width: map.width, height: map.height,
                             quality: depthData.depthDataQuality == .high ? "high" : "low",
                             accuracy: depthData.depthDataAccuracy == .absolute ? "absolute" : "relative",
                             calibration: depthData.cameraCalibrationData.map(CalibrationRecord.init))
        try write(info, to: folder.appendingPathComponent("\(name)_depth.json"))
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

    init(photo: UIImage?, lidar: DepthArray, stereo: DepthArray?, lidarCenters: [Double] = [], stereoCenters: [Double] = [],
         shake: Double? = nil, brightness: Double, folderName: String) {
        self.photo = photo
        self.folderName = folderName
        comparison = SensorComparison.compute(lidar: lidar.values, lidarSize: (lidar.width, lidar.height),
                                              stereo: stereo?.values, stereoSize: stereo.map { ($0.width, $0.height) },
                                              brightness: brightness, lidarCenters: lidarCenters,
                                              stereoCenters: stereoCenters, shake: shake)
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
    var shots: Int?
    /// Center distance of each shot, before merging.
    var stereoCenterMeters: [Double]?
    var lidarCenterMeters: [Double]?
    /// Gyroscope rotation rate when each shot was taken (stereo shots first, then LiDAR).
    var shakeRadiansPerSecond: [Double]?
    var orientationNote = "All images and depth maps are in sensor orientation; ignore EXIF orientation."
}
