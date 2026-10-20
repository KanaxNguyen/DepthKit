import SwiftUI

/// Spirit level with two automatic layouts:
/// - Edge: hold an edge of the iPhone against a surface; a horizon stays level with the world.
/// - Surface: lay the iPhone flat; a bubble floats toward the high side.
/// Turns green when level, says which way to adjust, shows slope in % and can measure from a reference.
struct LevelView: View {
    @Environment(HistoryModel.self) private var history
    @AppStorage(DevSettings.Key.levelTolerance, store: AppGroup.defaults) private var tolerance = DevSettings.Default.levelTolerance
    @State private var engine = LevelEngine()
    @State private var showSaved = false

    private var reading: LevelReading { engine.reading }
    private var isLevel: Bool { engine.isAvailable && reading.isLevel(tolerance: tolerance) }

    var body: some View {
        Group {
            if engine.isAvailable {
                content
            } else {
                SensorUnavailableView(title: "Motion Sensors Not Available",
                                      message: "Level needs an iPhone's motion sensors.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isLevel ? Color.green : Color(white: 0.07))
        .onAppear { engine.start() }
        .onDisappear { engine.stop() }
        .sensoryFeedback(.success, trigger: isLevel) { _, new in new }
        .animation(.easeInOut(duration: 0.2), value: isLevel)
        .animation(.snappy, value: reading.isFlat)
        .animation(.snappy, value: showSaved)
    }

    private var content: some View {
        ZStack {
            if reading.isFlat {
                SurfaceDial(roll: reading.surfaceRoll, pitch: reading.surfacePitch, isLevel: isLevel)
                    .transition(.opacity)
            } else {
                EdgeHorizon(deviation: reading.edgeDeviation, isLevel: isLevel)
                    .transition(.opacity)
            }

            VStack(spacing: 12) {
                if showSaved {
                    SavedToast()
                } else {
                    HintPill(text: reading.isFlat ? "Surface · lying flat" : "Edge · hold against a surface")
                }
                Spacer()
                panel
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private var panel: some View {
        let hint = reading.hint(tolerance: tolerance)
        return VStack(spacing: 14) {
            Label(hint.text, systemImage: hint.systemImage)
                .font(.title3.weight(.semibold))
                .contentTransition(.symbolEffect(.replace))

            HStack(spacing: 0) {
                if reading.isFlat {
                    Stat(title: "Left–Right", value: MeasureFormat.angle(abs(reading.surfaceRoll)))
                    Stat(title: "Front–Back", value: MeasureFormat.angle(abs(reading.surfacePitch)))
                } else {
                    Stat(title: "Angle", value: MeasureFormat.angle(abs(reading.edgeDeviation)))
                }
                Stat(title: "Slope", value: String(format: "%.1f%%", reading.slopePercent))
            }

            HStack(spacing: 28) {
                if reading.reference == nil {
                    HUDButton(title: "Measure From Here", systemImage: "scope") { engine.setReference() }
                } else {
                    HUDButton(title: "Clear Reference", systemImage: "xmark") { engine.clearReference() }
                }
                HUDButton(title: "Save", systemImage: "square.and.arrow.down", prominent: true) { save() }
            }

            if reading.reference != nil {
                Text("Measuring from your reference position")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .hudBackground(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func save() {
        history.add(MeasurementRecord(mode: .level, values: [reading.tilt]))
        showSaved = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showSaved = false
        }
    }
}

private struct Stat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A two-tone horizon that stays level with the world while the iPhone rotates.
private struct EdgeHorizon: View {
    let deviation: Double
    let isLevel: Bool

    var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height) * 2.5
            ZStack {
                Rectangle()
                    .fill(.white.opacity(isLevel ? 0.3 : 0.92))
                    .frame(width: side, height: side / 2)
                    .offset(y: side / 4)
                    .rotationEffect(.degrees(-deviation))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                // Fixed reference line: when it lines up with the horizon, the iPhone is level.
                Rectangle()
                    .fill(.white)
                    .frame(width: geo.size.width * 0.5, height: 2)
                    .blendMode(.difference)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2 - 70)

                Text(String(format: "%.1f°", abs(deviation)))
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: abs(deviation)))
                    .foregroundStyle(.white)
                    .blendMode(.difference)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .compositingGroup()
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel(String(format: "Tilted %.1f degrees", abs(deviation)))
    }
}

/// Target with rings at 1°, 5°, 10° and 15°; the bubble floats to the high side like a real bubble level.
private struct SurfaceDial: View {
    let roll: Double
    let pitch: Double
    let isLevel: Bool

    private let pointsPerDegree = 9.0
    private let maxDegrees = 15.0

    var body: some View {
        let radius = maxDegrees * pointsPerDegree
        ZStack {
            ForEach([1.0, 5.0, 10.0, 15.0], id: \.self) { degrees in
                Circle()
                    .stroke(.white.opacity(degrees == 1 ? 0.9 : 0.3), lineWidth: degrees == 1 ? 2 : 1)
                    .frame(width: degrees * pointsPerDegree * 2, height: degrees * pointsPerDegree * 2)
                if degrees >= 5 {
                    Text("\(Int(degrees))°")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .offset(x: degrees * pointsPerDegree + 12)
                }
            }
            Path { path in
                path.move(to: CGPoint(x: 0, y: radius)); path.addLine(to: CGPoint(x: radius * 2, y: radius))
                path.move(to: CGPoint(x: radius, y: 0)); path.addLine(to: CGPoint(x: radius, y: radius * 2))
            }
            .stroke(.white.opacity(0.3), lineWidth: 1)
            .frame(width: radius * 2, height: radius * 2)

            Circle()
                .fill(isLevel ? Color.white : Color.accentColor)
                .frame(width: 40, height: 40)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.3), radius: 4)
                .offset(bubbleOffset(radius: radius))
                .animation(.interactiveSpring(response: 0.2), value: roll)
                .animation(.interactiveSpring(response: 0.2), value: pitch)
        }
        .frame(width: radius * 2 + 60, height: radius * 2 + 60)
        .offset(y: -60)
        .accessibilityElement()
        .accessibilityLabel(String(format: "Left to right %.1f degrees, front to back %.1f degrees", abs(roll), abs(pitch)))
    }

    /// Right side low (roll > 0) pushes the bubble left; top edge low (pitch > 0) pushes it down.
    private func bubbleOffset(radius: Double) -> CGSize {
        var x = -roll * pointsPerDegree
        var y = pitch * pointsPerDegree
        let length = (x * x + y * y).squareRoot()
        if length > radius {
            x *= radius / length
            y *= radius / length
        }
        return CGSize(width: x, height: y)
    }
}
