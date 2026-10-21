import AVFoundation
import Observation

/// Streams depth from the front TrueDepth camera and reports the distance at the center of the view.
@Observable
final class TrueDepthEngine: NSObject, AVCaptureDepthDataOutputDelegate {
    static var isSupported: Bool {
        AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) != nil
    }

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let output = AVCaptureDepthDataOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "vn.kanax.depthkit.truedepth")
    @ObservationIgnored private var isConfigured = false
    @ObservationIgnored private var lastPublish = Date.distantPast

    var distance: Double?
    var isHighQuality = false
    /// Distance averaged over the last readings, with a 95 % interval.
    var estimate: Estimate?
    @ObservationIgnored let motion = MotionMonitor()
    @ObservationIgnored private var window = RollingWindow(capacity: DevSettings.Default.liveWindow)
    var errorMessage: String?

    func start() {
        motion.start()
        window = RollingWindow(capacity: max(1, DevSettings.liveWindow))
        queue.async { [self] in
            if !isConfigured { configure() }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        motion.stop()
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() {
        isConfigured = true
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .vga640x480

        guard let device = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            publishError("The TrueDepth camera is not available.")
            return
        }
        session.addInput(input)

        guard session.canAddOutput(output) else {
            publishError("Depth streaming is not available.")
            return
        }
        session.addOutput(output)
        output.isFilteringEnabled = DevSettings.trueDepthFiltering
        output.setDelegate(self, callbackQueue: queue)
        output.connection(with: .depthData)?.isEnabled = true

        let depthFormats = device.activeFormat.supportedDepthDataFormats.filter {
            let type = CMFormatDescriptionGetMediaSubType($0.formatDescription)
            return type == kCVPixelFormatType_DepthFloat32 || type == kCVPixelFormatType_DepthFloat16
        }
        if let best = depthFormats.max(by: {
            CMVideoFormatDescriptionGetDimensions($0.formatDescription).width
                < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width
        }), (try? device.lockForConfiguration()) != nil {
            device.activeDepthDataFormat = best
            device.unlockForConfiguration()
        }
    }

    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData,
                         timestamp: CMTime, connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastPublish) > 0.08 else { return }
        lastPublish = now

        let converted = depthData.depthDataType == kCVPixelFormatType_DepthFloat32
            ? depthData : depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = PixelBuffers.floats(converted.depthDataMap)
        let value = PixelBuffers.centerMedian(depth: map.values, width: map.width, height: map.height, window: 9)
        let high = depthData.depthDataQuality == .high
        DispatchQueue.main.async {
            self.distance = value
            self.isHighQuality = high
            self.window.add(value)
            self.estimate = self.window.estimate
        }
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async { self.errorMessage = message }
    }
}
