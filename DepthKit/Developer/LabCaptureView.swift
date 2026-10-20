import SwiftUI

/// One-tap comparison of LiDAR and two-camera (stereo) depth. The raw capture is also saved for optional
/// analysis on a Mac (lab/README.md).
struct LabCaptureView: View {
    /// Shown inside the Measure tab rather than pushed from Developer settings.
    var embedded = false

    @AppStorage(SharedSettings.unitsKey, store: AppGroup.defaults) private var units: UnitSystem = .metric
    @State private var engine = LabCaptureEngine()
    @State private var result: LabResult?

    var body: some View {
        Group {
            if LabCaptureEngine.isSupported {
                content
            } else {
                SensorUnavailableView(title: "LiDAR Needed",
                                      message: "Compare Sensors needs an iPhone Pro with a LiDAR Scanner.")
            }
        }
        .navigationTitle("Compare Sensors")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(embedded ? .automatic : .hidden, for: .tabBar)
        .sheet(item: $result) { result in
            ComparisonSheet(result: result, units: units)
                .presentationDetents([.medium, .large])
        }
    }

    private var content: some View {
        ZStack {
            CameraPreview(session: engine.session)
                .ignoresSafeArea()

            Crosshair()

            VStack(spacing: 12) {
                HintPill(text: engine.isCapturing
                         ? (engine.steps.last ?? "Hold still…")
                         : "Point at an object, tap Compare, hold still ~4 s")

                Spacer()

                if let message = engine.resultMessage {
                    Text(message)
                        .font(.callout)
                        .padding(12)
                        .hudBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Button {
                    Task {
                        await engine.capture(label: "", tapeDistance: nil)
                        result = engine.lastResult
                    }
                } label: {
                    Label(engine.isCapturing ? "Measuring…" : "Compare", systemImage: "square.split.2x1")
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
        .sensoryFeedback(.success, trigger: result?.id) { _, new in new != nil }
    }
}

private struct ComparisonSheet: View {
    let result: LabResult
    let units: UnitSystem

    private var c: SensorComparison { result.comparison }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(c.verdict)
                        .font(.headline)
                    if let note = c.darkNote {
                        Label(note, systemImage: "moon.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Distance at the Center") {
                    LabeledContent("LiDAR (laser)", value: c.lidarCenter.map { MeasureFormat.length($0, units: units) } ?? "—")
                    LabeledContent("Two Cameras (stereo)") {
                        Text(stereoText)
                    }
                }

                Section {
                    LabeledContent("Average Difference",
                                   value: c.wholeImageError.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                    LabeledContent("Stereo Found Depth In", value: String(format: "%.0f%% of the image", c.stereoCoverage * 100))
                    LabeledContent("Brightness", value: c.isDark ? "Dark" : String(format: "%.0f%%", c.brightness * 100))
                } header: {
                    Text("Whole Image")
                }

                Section {
                    HStack(spacing: 8) {
                        DepthTile(title: "LiDAR", image: result.lidarImage)
                        DepthTile(title: "Two Cameras", image: result.stereoImage)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                } header: {
                    Text("Depth Maps")
                } footer: {
                    Text("Red is near, blue is far, black is no depth. Saved as \(result.folderName) in Files › DepthKit › LabCaptures for deeper analysis on a Mac.")
                }
            }
            .navigationTitle("Result")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var stereoText: String {
        guard let s = c.stereoCenter else { return "No depth" }
        var text = MeasureFormat.length(s, units: units)
        if let d = c.centerDifference { text += String(format: "  (%+.0f%%)", d * 100) }
        return text
    }
}

private struct DepthTile: View {
    let title: String
    let image: CGImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image {
                    // Depth maps are in sensor (landscape) orientation; show them upright.
                    Image(decorative: image, scale: 1, orientation: .right)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.black.overlay(Text("No depth").font(.caption).foregroundStyle(.white))
                        .aspectRatio(3 / 4, contentMode: .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title).font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }
}
