import SwiftUI

/// Tripod capture screen for the multi-camera depth experiment.
struct LabCaptureView: View {
    @State private var engine = LabCaptureEngine()
    @State private var label = ""
    @State private var tapeDistance = ""
    @State private var captures = LabCaptureEngine.summary()
    @FocusState private var editing: Bool

    var body: some View {
        Group {
            if LabCaptureEngine.isSupported {
                content
            } else {
                SensorUnavailableView(title: "LiDAR Depth Camera Needed",
                                      message: "Lab Capture needs an iPhone Pro with a LiDAR Scanner and several back cameras.")
            }
        }
        .navigationTitle("Lab Capture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private var content: some View {
        ZStack {
            CameraPreview(session: engine.session)
                .ignoresSafeArea()
                .onTapGesture { editing = false }

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Put iPhone on a tripod. One capture takes about 4 seconds; keep the scene still.")
                    Text("Saved: \(captures) · Files › DepthKit › LabCaptures")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .hudBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Spacer()

                if !engine.steps.isEmpty || engine.resultMessage != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(engine.steps, id: \.self) { Text($0) }
                        if let message = engine.resultMessage {
                            Text(message).fontWeight(.semibold)
                        }
                    }
                    .font(.callout.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .hudBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                VStack(spacing: 10) {
                    TextField("Label, e.g. box-1.5m-night", text: $label)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($editing)
                    Divider()
                    TextField("Tape-measured distance to target (m), optional", text: $tapeDistance)
                        .keyboardType(.decimalPad)
                        .focused($editing)
                }
                .padding(12)
                .hudBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button {
                    editing = false
                    Task {
                        await engine.capture(label: label, tapeDistance: Double(tapeDistance.replacingOccurrences(of: ",", with: ".")))
                        captures = LabCaptureEngine.summary()
                    }
                } label: {
                    Label(engine.isCapturing ? "Capturing…" : "Capture", systemImage: "camera.aperture")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(engine.isCapturing)
            }
            .padding(16)
        }
        .onAppear { engine.startPreview() }
        .onDisappear { engine.stop() }
        .sensoryFeedback(.success, trigger: engine.resultMessage) { _, new in new?.hasPrefix("Saved") == true }
    }
}
