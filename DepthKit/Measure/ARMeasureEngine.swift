import ARKit
import Observation
import RealityKit
import simd

/// Runs the LiDAR session and turns frames into readings for the Distance, Range and Box modes.
@Observable
final class ARMeasureEngine: NSObject, ARSessionDelegate {
    static var isSupported: Bool { ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) }

    @ObservationIgnored let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)

    // Readings published at ~20 Hz.
    var trackingHint: String?
    var centerDepth: Double?
    var centerIsHighConfidence = false
    /// Center distance averaged over the last readings, with a 95 % interval (steadies a shaking hand).
    var centerEstimate: Estimate?
    @ObservationIgnored let motion = MotionMonitor()
    var hitPoint: SIMD3<Float>?
    var floorY: Float?

    // Distance mode.
    var points: [SIMD3<Float>] = []
    /// True while a tapped point is being averaged over several frames.
    var isPlacingPoint = false
    var screenPoints: [CGPoint] = []
    var screenHit: CGPoint?

    // Box mode.
    var box: BoxEstimate?
    var screenBox: [CGPoint?] = []
    var isCapturingBox = false
    var boxFailed = false

    // Developer tools.
    var stats: DepthStats?
    var debugImage: CGImage?
    var captureMessage: String?

    @ObservationIgnored private var boxSamples: [BoxEstimate] = []
    @ObservationIgnored private var boxFramesTried = 0
    @ObservationIgnored private var boxOptions = BoxEstimator.Options()
    @ObservationIgnored private var boxFramesWanted = DevSettings.Default.boxFrames
    @ObservationIgnored private var lastRegion: Set<Int> = []
    @ObservationIgnored private var centerWindow = RollingWindow(capacity: DevSettings.Default.liveWindow)
    @ObservationIgnored private var pointSamples: [SIMD3<Float>] = []
    private static let pointSampleCount = 8
    @ObservationIgnored private var pendingCaptureMode: MeasureMode?
    @ObservationIgnored private var lastPublish: TimeInterval = 0
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private let captureQueue = DispatchQueue(label: "vn.kanax.depthkit.capture")

    override init() {
        super.init()
        arView.session.delegate = self
        arView.renderOptions.insert(.disableMotionBlur)
    }

    func start() {
        guard Self.isSupported, !isRunning else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.frameSemantics = ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)
            ? [.smoothedSceneDepth] : [.sceneDepth]
        arView.session.run(configuration)
        motion.start()
        isRunning = true
    }

    func pause() {
        arView.session.pause()
        motion.stop()
        isRunning = false
    }

    func resetReadings() {
        points = []
        pointSamples = []
        isPlacingPoint = false
        centerWindow.reset()
        centerEstimate = nil
        screenPoints = []
        box = nil
        screenBox = []
        boxSamples = []
        lastRegion = []
        isCapturingBox = false
        boxFailed = false
    }

    // MARK: Distance

    /// Adds the point under the crosshair, averaged over the next few frames so a shaking hand doesn't
    /// move it; a third tap starts a new measurement.
    func addPoint() {
        guard hitPoint != nil, !isPlacingPoint else { return }
        if points.count >= 2 { points = [] }
        pointSamples = []
        isPlacingPoint = true
    }

    /// Per-axis median of the sampled hit points.
    static func medianPoint(_ samples: [SIMD3<Float>]) -> SIMD3<Float>? {
        guard !samples.isEmpty else { return nil }
        func med(_ values: [Float]) -> Float { values.sorted()[values.count / 2] }
        return SIMD3(med(samples.map(\.x)), med(samples.map(\.y)), med(samples.map(\.z)))
    }

    var distanceResult: Double? {
        if points.count == 2 { return Double(simd_distance(points[0], points[1])) }
        if points.count == 1, let hitPoint { return Double(simd_distance(points[0], hitPoint)) }
        return nil
    }

    // MARK: Box

    func captureBox() {
        box = nil
        boxSamples = []
        boxFramesTried = 0
        boxFailed = false
        boxOptions = DevSettings.boxOptions
        boxFramesWanted = max(1, DevSettings.boxFrames)
        isCapturingBox = true
    }

    // MARK: Dataset capture

    /// Saves the next frame as an RGB + depth sample.
    func captureSample(mode: MeasureMode) {
        pendingCaptureMode = mode
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        updateFloor(frame)
        if isCapturingBox { sampleBox(frame) }
        if let mode = pendingCaptureMode {
            pendingCaptureMode = nil
            saveSample(frame, mode: mode)
        }

        guard frame.timestamp - lastPublish > 0.05 else { return }
        lastPublish = frame.timestamp

        trackingHint = Self.hint(for: frame.camera.trackingState)

        if let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth {
            let depth = PixelBuffers.floats(depthData.depthMap)
            let confidence = depthData.confidenceMap.map(PixelBuffers.bytes)
            let window = DevSettings.readoutWindow
            centerDepth = PixelBuffers.centerMedian(depth: depth.values, width: depth.width, height: depth.height,
                                                    confidence: confidence, minConfidence: DevSettings.readoutMinConfidence,
                                                    window: window)
            centerIsHighConfidence = PixelBuffers.centerMedian(depth: depth.values, width: depth.width, height: depth.height,
                                                               confidence: confidence, minConfidence: 2, window: window) != nil
            centerWindow.capacity = max(1, DevSettings.liveWindow)
            centerWindow.add(centerDepth)
            centerEstimate = centerWindow.estimate
            stats = DevSettings.showStats ? DepthStats.compute(depth: depth.values, confidence: confidence) : nil
            debugImage = DevSettings.showHeatmap
                ? DepthColormap.image(depth: depth.values, width: depth.width, height: depth.height,
                                      confidence: confidence, highlight: lastRegion)
                : nil
        }

        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        if let result = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .any).first {
            let t = result.worldTransform.columns.3
            hitPoint = SIMD3(t.x, t.y, t.z)
        } else {
            hitPoint = nil
        }
        if isPlacingPoint, let hitPoint {
            pointSamples.append(hitPoint)
            if pointSamples.count >= Self.pointSampleCount, let point = Self.medianPoint(pointSamples) {
                points.append(point)
                isPlacingPoint = false
            }
        }

        screenPoints = points.compactMap { arView.project($0) }
        screenHit = hitPoint.flatMap { arView.project($0) }
        screenBox = box?.corners.map { arView.project($0) } ?? []
    }

    private func updateFloor(_ frame: ARFrame) {
        let planes = frame.anchors.compactMap { $0 as? ARPlaneAnchor }.filter { $0.alignment == .horizontal }
        guard !planes.isEmpty else { return }
        let floors = planes.filter { $0.classification == .floor }
        let candidates = floors.isEmpty ? planes : floors
        floorY = candidates.map { $0.transform.columns.3.y }.min()
    }

    private func sampleBox(_ frame: ARFrame) {
        boxFramesTried += 1
        if let floorY, let depthFrame = Self.depthFrame(from: frame) {
            let analysis = BoxEstimator.analyze(depthFrame, floorY: floorY, options: boxOptions)
            lastRegion = Set(analysis.region)
            if let estimate = analysis.estimate { boxSamples.append(estimate) }
        }
        if boxSamples.count >= boxFramesWanted {
            box = BoxEstimator.combine(boxSamples)
            isCapturingBox = false
        } else if boxFramesTried >= boxFramesWanted * 8 {
            isCapturingBox = false
            boxFailed = true
        }
    }

    private func saveSample(_ frame: ARFrame, mode: MeasureMode) {
        guard let data = frame.smoothedSceneDepth ?? frame.sceneDepth else {
            captureMessage = "No depth in this frame"
            return
        }
        let depth = PixelBuffers.floats(data.depthMap)
        let confidence = data.confidenceMap.map(PixelBuffers.bytes)
        let image = frame.camera.imageResolution
        let k = frame.camera.intrinsics
        let t = frame.camera.transform
        let sample = DatasetSample(
            timestamp: Date(), device: DatasetWriter.deviceModel, mode: mode.rawValue,
            imageWidth: Int(image.width), imageHeight: Int(image.height),
            depthWidth: depth.width, depthHeight: depth.height,
            intrinsics: [k[0][0], k[0][1], k[0][2], k[1][0], k[1][1], k[1][2], k[2][0], k[2][1], k[2][2]],
            cameraToWorld: (0..<4).flatMap { c in (0..<4).map { r in t[c][r] } },
            floorY: floorY
        )
        let rgb = frame.capturedImage
        captureMessage = "Saving…"
        captureQueue.async { [weak self] in
            let preview = DepthColormap.image(depth: depth.values, width: depth.width, height: depth.height, confidence: confidence)
            let message: String
            do {
                try DatasetWriter.save(sample: sample, rgbJPEG: DatasetWriter.jpeg(from: rgb), depth: depth.values,
                                       confidence: confidence, preview: preview)
                message = "Sample saved"
            } catch {
                message = "Save failed: \(error.localizedDescription)"
            }
            DispatchQueue.main.async { self?.captureMessage = message }
        }
    }

    private static func depthFrame(from frame: ARFrame) -> DepthFrame? {
        guard let data = frame.smoothedSceneDepth ?? frame.sceneDepth else { return nil }
        let depth = PixelBuffers.floats(data.depthMap)
        let confidence = data.confidenceMap.map(PixelBuffers.bytes)
        let image = frame.camera.imageResolution
        let sx = Float(depth.width) / Float(image.width)
        let sy = Float(depth.height) / Float(image.height)
        var k = frame.camera.intrinsics
        k[0][0] *= sx; k[2][0] *= sx
        k[1][1] *= sy; k[2][1] *= sy
        return DepthFrame(width: depth.width, height: depth.height, depth: depth.values,
                          confidence: confidence, intrinsics: k, cameraToWorld: frame.camera.transform)
    }

    private static func hint(for state: ARCamera.TrackingState) -> String? {
        switch state {
        case .normal: nil
        case .notAvailable: "Tracking unavailable"
        case .limited(.initializing): "Move your iPhone slowly to start"
        case .limited(.excessiveMotion): "Slow down"
        case .limited(.insufficientFeatures): "Point at a surface with more detail"
        case .limited(.relocalizing): "Hold still"
        case .limited: "Tracking limited"
        }
    }
}
