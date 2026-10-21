import ARKit
import RealityKit
import SwiftUI

struct LiDARMeasureView: View {
    let mode: MeasureMode

    var body: some View {
        if ARMeasureEngine.isSupported {
            LiDARSessionView(mode: mode)
        } else {
            SensorUnavailableView(
                title: "LiDAR Not Available",
                message: "Two-point distance, back-camera distance and Box need an iPhone with a LiDAR Scanner (Pro models)."
            )
        }
    }
}

private struct LiDARSessionView: View {
    let mode: MeasureMode

    @Environment(HistoryModel.self) private var history
    @AppStorage(SharedSettings.unitsKey, store: AppGroup.defaults) private var units: UnitSystem = .metric
    @AppStorage(SharedSettings.divisorKey, store: AppGroup.defaults) private var divisor: Double = 5000
    @AppStorage(DevSettings.Key.enabled, store: AppGroup.defaults) private var devEnabled = false
    @State private var engine = ARMeasureEngine()
    @State private var showSaved = false

    var body: some View {
        ZStack {
            ARViewContainer(engine: engine)
                .ignoresSafeArea()

            if let heatmap = engine.debugImage {
                // The depth map is in sensor (landscape) orientation; rotate it to match the portrait camera view.
                Color.clear
                    .overlay {
                        Image(decorative: heatmap, scale: 1, orientation: .right)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .opacity(0.6)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            overlay
                .allowsHitTesting(false)
                .ignoresSafeArea()

            Crosshair()

            VStack(spacing: 12) {
                if devEnabled {
                    DevToolbar(stats: engine.stats, centerDepth: engine.centerDepth, floorY: engine.floorY,
                               message: engine.captureMessage) {
                        engine.captureSample(mode: mode)
                    }
                }
                if showSaved {
                    SavedToast()
                } else if let hint {
                    HintPill(text: hint)
                }
                Spacer()
                readout
                controls
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .onAppear { engine.start() }
        .onDisappear { engine.pause() }
        .onChange(of: mode) { engine.resetReadings() }
        .sensoryFeedback(.success, trigger: showSaved) { _, new in new }
        .sensoryFeedback(.impact(weight: .light), trigger: engine.points.count)
        .animation(.snappy, value: showSaved)
    }

    // MARK: Overlay drawing

    private var overlay: some View {
        Canvas { context, _ in
            let accent = Color.accentColor
            if mode == .distance {
                var targets = engine.screenPoints
                if engine.points.count == 1, let hit = engine.screenHit { targets.append(hit) }
                if targets.count == 2 {
                    var line = Path()
                    line.move(to: targets[0]); line.addLine(to: targets[1])
                    context.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: engine.points.count == 2 ? [] : [8, 6]))
                }
                for point in engine.screenPoints {
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)), with: .color(accent))
                    context.stroke(Path(ellipseIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)), with: .color(.white), lineWidth: 2)
                }
            }
            if mode == .box, engine.screenBox.count == 8 {
                var path = Path()
                for (a, b) in BoxEstimate.edges {
                    guard let p = engine.screenBox[a], let q = engine.screenBox[b] else { continue }
                    path.move(to: p); path.addLine(to: q)
                }
                context.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            }
        }
    }

    // MARK: Hints, readouts, controls

    private var hint: String? {
        if let tracking = engine.trackingHint { return tracking }
        switch mode {
        case .distance:
            if engine.isPlacingPoint { return "Hold steady…" }
            return engine.points.isEmpty ? "Aim at the start point and tap +" : (engine.points.count == 1 ? "Aim at the end point and tap +" : nil)
        case .range:
            return engine.motion.isSteady ? nil : "Hold steady for a tighter reading"
        case .box:
            if engine.floorY == nil { return "Point at the floor around the box" }
            if engine.isCapturingBox { return "Hold still…" }
            if engine.boxFailed { return "No box under the crosshair. Step back so the whole box is in view." }
            return engine.box == nil ? "Aim at the top of the box and tap Measure" : nil
        default:
            return nil
        }
    }

    @ViewBuilder
    private var readout: some View {
        switch mode {
        case .distance:
            ReadoutCard(title: "Two Points", value: engine.distanceResult.map { MeasureFormat.length($0, units: units) }) {
                Text("Back camera · LiDAR")
            }
        case .range:
            ReadoutCard(title: "From iPhone", value: (engine.centerEstimate?.value ?? engine.centerDepth).map { MeasureFormat.length($0, units: units) }) {
                LiveIntervalLabel(estimate: engine.centerEstimate, steady: engine.motion.isSteady,
                                  highConfidence: engine.centerIsHighConfidence, units: units)
            }
        case .box:
            ReadoutCard(title: "Box", value: engine.box.map { MeasureFormat.box($0.dimensions, units: units) },
                        placeholder: engine.isCapturingBox ? "Measuring…" : "—") {
                if let box = engine.box {
                    Text(String(format: "%.1f L  ·  %.1f kg dimensional weight (÷%.0f)",
                                DimensionalWeight.liters(box.dimensions),
                                DimensionalWeight.kilograms(box.dimensions, divisor: divisor), divisor))
                } else {
                    Text("Length × Width × Height")
                }
            }
        default:
            EmptyView()
        }
    }

    private var controls: some View {
        HStack(spacing: 28) {
            HUDButton(title: "Reset", systemImage: "arrow.counterclockwise") { engine.resetReadings() }

            switch mode {
            case .distance:
                HUDButton(title: "Add Point", systemImage: "plus", prominent: true) { engine.addPoint() }
                    .disabled(engine.hitPoint == nil || engine.isPlacingPoint)
            case .box:
                HUDButton(title: "Measure Box", systemImage: "viewfinder", prominent: true) { engine.captureBox() }
                    .disabled(engine.floorY == nil || engine.isCapturingBox)
            default:
                HUDButton(title: "Save", systemImage: "square.and.arrow.down", prominent: true) { save() }
                    .disabled(engine.centerDepth == nil)
            }

            // Range saves from the main button; keep the slot so the layout doesn't jump.
            HUDButton(title: "Save", systemImage: "checkmark") { save() }
                .disabled(!canSave || mode == .range)
                .opacity(mode == .range ? 0 : 1)
                .accessibilityHidden(mode == .range)
        }
    }

    private var canSave: Bool {
        switch mode {
        case .distance: engine.points.count == 2
        case .range: engine.centerDepth != nil
        case .box: engine.box != nil
        default: false
        }
    }

    private func save() {
        let values: [Double]
        switch mode {
        case .distance:
            guard engine.points.count == 2, let d = engine.distanceResult else { return }
            values = [d]
        case .range:
            guard let d = engine.centerEstimate?.value ?? engine.centerDepth else { return }
            values = [d]
        case .box:
            guard let box = engine.box else { return }
            values = box.dimensions
        default:
            return
        }
        history.add(MeasurementRecord(mode: mode, values: values))
        showSaved = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showSaved = false
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    let engine: ARMeasureEngine

    func makeUIView(context: Context) -> ARView {
        let view = engine.arView
        let coaching = ARCoachingOverlayView()
        coaching.session = view.session
        coaching.goal = .horizontalPlane
        coaching.activatesAutomatically = true
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(coaching)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

/// Developer stats and the dataset capture button, shown when Developer Mode is on.
private struct DevToolbar: View {
    let stats: DepthStats?
    let centerDepth: Double?
    let floorY: Float?
    let message: String?
    let capture: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if let stats {
                    Text(String(format: "valid %.0f%%  high %.0f%%", stats.validFraction * 100, stats.highConfidenceFraction * 100))
                    Text("range " + (stats.minDepth.map { String(format: "%.2f", $0) } ?? "–") + "–"
                         + (stats.maxDepth.map { String(format: "%.2f m", $0) } ?? "–"))
                }
                Text("center " + (centerDepth.map { String(format: "%.3f m", $0) } ?? "–")
                     + "  floor " + (floorY.map { String(format: "%.2f", $0) } ?? "–"))
                if let message { Text(message).foregroundStyle(.secondary) }
            }
            .font(.caption.monospacedDigit())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .hudBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Spacer(minLength: 0)

            Button(action: capture) {
                Image(systemName: "camera.aperture")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .hudBackground(in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Capture RGB and depth sample")
        }
    }
}

/// "± 0.6 cm · 95%" with a steadiness and confidence cue, for live readings.
struct LiveIntervalLabel: View {
    let estimate: Estimate?
    let steady: Bool
    var highConfidence = true
    let units: UnitSystem

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: steady ? "hand.raised.fill" : "hand.raised.slash.fill")
                .foregroundStyle(steady ? Color.green : Color.orange)
            if let margin = estimate?.margin {
                Text("± \(MeasureFormat.length(margin, units: units)) · 95%")
                    .monospacedDigit()
            } else {
                Text("Collecting…")
            }
            if !highConfidence {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [steady ? "Steady" : "Shaking"]
        if let margin = estimate?.margin { parts.append("plus or minus \(MeasureFormat.length(margin, units: units))") }
        if !highConfidence { parts.append("low sensor confidence") }
        return parts.joined(separator: ", ")
    }
}
