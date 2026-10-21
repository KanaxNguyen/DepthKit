import SwiftUI

/// On-device tuning for the measuring algorithms, debug overlays and dataset capture.
struct DeveloperView: View {
    @AppStorage(DevSettings.Key.enabled, store: AppGroup.defaults) private var enabled = false
    @AppStorage(DevSettings.Key.showStats, store: AppGroup.defaults) private var showStats = DevSettings.Default.showStats
    @AppStorage(DevSettings.Key.showHeatmap, store: AppGroup.defaults) private var showHeatmap = DevSettings.Default.showHeatmap
    @AppStorage(DevSettings.Key.readoutMinConfidence, store: AppGroup.defaults) private var readoutMinConfidence = DevSettings.Default.readoutMinConfidence
    @AppStorage(DevSettings.Key.readoutWindow, store: AppGroup.defaults) private var readoutWindow = DevSettings.Default.readoutWindow
    @AppStorage(DevSettings.Key.boxMinHeightCm, store: AppGroup.defaults) private var boxMinHeightCm = DevSettings.Default.boxMinHeightCm
    @AppStorage(DevSettings.Key.boxMinConfidence, store: AppGroup.defaults) private var boxMinConfidence = DevSettings.Default.boxMinConfidence
    @AppStorage(DevSettings.Key.boxFrames, store: AppGroup.defaults) private var boxFrames = DevSettings.Default.boxFrames
    @AppStorage(DevSettings.Key.boxHeightPercentile, store: AppGroup.defaults) private var boxHeightPercentile = DevSettings.Default.boxHeightPercentile
    @AppStorage(DevSettings.Key.boxJumpCm, store: AppGroup.defaults) private var boxJumpCm = DevSettings.Default.boxJumpCm
    @AppStorage(DevSettings.Key.boxMinPoints, store: AppGroup.defaults) private var boxMinPoints = DevSettings.Default.boxMinPoints
    @AppStorage(DevSettings.Key.trueDepthFiltering, store: AppGroup.defaults) private var trueDepthFiltering = DevSettings.Default.trueDepthFiltering
    @AppStorage(DevSettings.Key.levelTolerance, store: AppGroup.defaults) private var levelTolerance = DevSettings.Default.levelTolerance

    @AppStorage(DevSettings.Key.compareShots, store: AppGroup.defaults) private var compareShots = DevSettings.Default.compareShots
    @AppStorage(DevSettings.Key.liveWindow, store: AppGroup.defaults) private var liveWindow = DevSettings.Default.liveWindow
    @State private var dataset = DatasetWriter.summary()
    @State private var confirmDelete = false
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Toggle("Developer Mode", isOn: $enabled)
            } footer: {
                Text("Shows depth stats and a capture button on the LiDAR screens. Parameters below apply whether or not Developer Mode is on.")
            }

            Section("Overlays") {
                Toggle("Depth Stats", isOn: $showStats)
                Toggle("Depth Heatmap", isOn: $showHeatmap)
            }
            .disabled(!enabled)

            Section {
                ConfidencePicker(title: "Minimum Confidence", selection: $readoutMinConfidence)
                Stepper("Center Window: \(readoutWindow) px", value: $readoutWindow, in: 1...21, step: 2)
            } header: {
                Text("Distance From iPhone")
            } footer: {
                Text("The back-camera distance is the median depth of a square of pixels at the crosshair, ignoring pixels below this confidence.")
            }

            Section {
                SliderRow(title: "Min Height Above Floor", value: $boxMinHeightCm, range: 0.5...6, step: 0.5, format: "%.1f cm")
                ConfidencePicker(title: "Minimum Confidence", selection: $boxMinConfidence)
                SliderRow(title: "Edge Depth Jump", value: $boxJumpCm, range: 1...8, step: 0.5, format: "%.1f cm")
                SliderRow(title: "Height Percentile", value: $boxHeightPercentile, range: 0.80...0.995, step: 0.005, format: "%.3f")
                Stepper("Frames to Average: \(boxFrames)", value: $boxFrames, in: 1...40)
                Stepper("Min Region Pixels: \(boxMinPoints)", value: $boxMinPoints, in: 50...2000, step: 50)
            } header: {
                Text("Box Estimator")
            } footer: {
                Text("Pixels higher than Min Height join the box region while neighbouring depth changes by less than Edge Depth Jump. Height is taken at the chosen percentile to ignore spikes. Turn on Depth Heatmap to see the region in white.")
            }

            Section {
                Stepper("Compare Shots per Sensor: \(compareShots)", value: $compareShots, in: 1...15)
                Stepper("Live Window: \(liveWindow) readings (~\(String(format: "%.1f", Double(liveWindow) / 20)) s)",
                        value: $liveWindow, in: 5...60, step: 5)
            } header: {
                Text("Hand Shake")
            } footer: {
                Text("Compare waits for a steady hand before each shot and merges the shots; live distances average the last readings. More shots or a longer window narrow the ± interval but take longer.")
            }

            Section("TrueDepth") {
                Toggle("System Depth Filtering", isOn: $trueDepthFiltering)
            }

            Section("Level") {
                SliderRow(title: "Level Tolerance", value: $levelTolerance, range: 0.1...2, step: 0.1, format: "%.1f°")
            }

            Section {
                LabeledContent("Samples", value: "\(dataset.count)")
                LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: dataset.bytes, countStyle: .file))
                Button("Delete All Samples", role: .destructive) { confirmDelete = true }
                    .disabled(dataset.count == 0)
            } header: {
                Text("Dataset")
            } footer: {
                Text("Tap the aperture button on a LiDAR screen to save the RGB image, the depth map, the confidence map, the intrinsics and the camera pose. Find the samples in Files › On My iPhone › DepthKit › Captures. They can be used to fine-tune or evaluate a depth model.")
            }

            Section {
                NavigationLink {
                    LabCaptureView()
                } label: {
                    Label("Compare Sensors", systemImage: "square.split.2x1")
                }
            } header: {
                Text("Experiment")
            } footer: {
                Text("Point at something and tap once: see how far the two-camera (stereo) depth is from LiDAR, by day or at night. Each capture is also saved for optional deeper analysis on a Mac.")
            }

            Section {
                Button("Reset Parameters to Defaults") { confirmReset = true }
            }
        }
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { dataset = DatasetWriter.summary() }
        .confirmationDialog("Delete all samples?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) {
                DatasetWriter.deleteAll()
                dataset = DatasetWriter.summary()
            }
        }
        .confirmationDialog("Reset all parameters?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { DevSettings.resetToDefaults() }
        }
    }
}

private struct ConfidencePicker: View {
    let title: String
    @Binding var selection: Int

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Low").tag(0)
            Text("Medium").tag(1)
            Text("High").tag(2)
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title, value: String(format: format, value))
            Slider(value: $value, in: range, step: step)
                .accessibilityLabel(title)
        }
    }
}
