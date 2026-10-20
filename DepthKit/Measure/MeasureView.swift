import SwiftUI

struct MeasureView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        Group {
            // LiDAR modes share one view so switching between them keeps the AR session running.
            if router.tool == .distance && router.distanceMethod == .compare {
                LabCaptureView(embedded: true)
            } else if router.mode.usesLiDAR {
                LiDARMeasureView(mode: router.mode)
            } else if router.mode == .near {
                TrueDepthMeasureView()
            } else {
                LevelView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                if router.tool == .distance {
                    DistanceMethodBar(method: $router.distanceMethod, sensor: $router.distanceSensor)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                ModeSwitcher(selection: $router.tool)
            }
            .padding(.bottom, 12)
            .animation(.snappy, value: router.tool)
        }
    }
}

/// Two Points / From iPhone, plus a camera-flip button to choose the back LiDAR or the front TrueDepth camera.
private struct DistanceMethodBar: View {
    @Binding var method: DistanceMethod
    @Binding var sensor: DistanceSensor

    private var canFlip: Bool { ARMeasureEngine.isSupported && TrueDepthEngine.isSupported }

    var body: some View {
        HStack(spacing: 8) {
            Picker("Method", selection: $method) {
                ForEach(DistanceMethod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: method == .fromPhone ? 270 : 330)

            if method == .fromPhone {
                Button {
                    withAnimation(.snappy) { sensor = sensor == .lidar ? .trueDepth : .lidar }
                } label: {
                    Label(sensor == .lidar ? "Back" : "Front", systemImage: "arrow.triangle.2.circlepath.camera")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!canFlip)
                .accessibilityLabel(sensor == .lidar ? "Using back LiDAR. Switch to front TrueDepth" : "Using front TrueDepth. Switch to back LiDAR")
                .transition(.opacity)
            }
        }
        .padding(6)
        .hudBackground(in: Capsule())
        .animation(.snappy, value: method)
    }
}

/// Toast shown after saving.
struct SavedToast: View {
    var body: some View {
        Label("Saved to History", systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .hudBackground(in: Capsule())
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Explains why a mode can't run here and points to what can.
struct SensorUnavailableView: View {
    let title: String
    let message: String

    private var alternatives: String {
        var tools: [String] = []
        if ARMeasureEngine.isSupported { tools += ["Distance", "Box"] }
        if TrueDepthEngine.isSupported { tools.append("Distance from iPhone (front camera)") }
        if LevelEngine.isSupported { tools.append("Level") }
        guard !tools.isEmpty else { return "This device has no depth or motion sensors. Try DepthKit on an iPhone." }
        return "Available here: " + ListFormatter.localizedString(byJoining: tools) + "."
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "sensor")
        } description: {
            Text(message + "\n\n" + alternatives)
        }
        .foregroundStyle(.white)
    }
}
