import AVFoundation
import SwiftUI

struct TrueDepthMeasureView: View {
    var body: some View {
        if TrueDepthEngine.isSupported {
            TrueDepthSessionView()
        } else {
            SensorUnavailableView(
                title: "TrueDepth Not Available",
                message: "Near needs an iPhone with Face ID."
            )
        }
    }
}

private struct TrueDepthSessionView: View {
    @Environment(HistoryModel.self) private var history
    @AppStorage(SharedSettings.unitsKey, store: AppGroup.defaults) private var units: UnitSystem = .metric
    @State private var engine = TrueDepthEngine()
    @State private var showSaved = false

    var body: some View {
        ZStack {
            CameraPreview(session: engine.session)
                .ignoresSafeArea()

            Crosshair()

            VStack(spacing: 12) {
                if showSaved {
                    SavedToast()
                } else {
                    HintPill(text: engine.errorMessage ?? "Front camera · best from 20 cm to 1 m")
                }
                Spacer()
                ReadoutCard(title: "Near", value: engine.distance.map { MeasureFormat.length($0, units: units) }) {
                    Label(engine.isHighQuality ? "High quality depth" : "Low quality depth",
                          systemImage: engine.isHighQuality ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                }
                HUDButton(title: "Save", systemImage: "square.and.arrow.down", prominent: true) { save() }
                    .disabled(engine.distance == nil)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 84)
        }
        .onAppear { engine.start() }
        .onDisappear { engine.stop() }
        .sensoryFeedback(.success, trigger: showSaved) { _, new in new }
        .animation(.snappy, value: showSaved)
    }

    private func save() {
        guard let distance = engine.distance else { return }
        history.add(MeasurementRecord(mode: .near, values: [distance]))
        showSaved = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showSaved = false
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
