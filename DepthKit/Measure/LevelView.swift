import SwiftUI

/// Spirit level drawn as one round gauge on a dark background.
/// - Edge (held on an edge): an artificial horizon rotates inside the gauge and stays level with the world.
/// - Surface (lying flat): a bubble floats toward the high side.
/// The gauge and the number turn green when level; the hint says which way to adjust.
struct LevelView: View {
    @Environment(HistoryModel.self) private var history
    @AppStorage(DevSettings.Key.levelTolerance, store: AppGroup.defaults) private var tolerance = DevSettings.Default.levelTolerance
    @State private var engine = LevelEngine()
    @State private var showSaved = false

    private var reading: LevelReading { engine.reading }
    private var isLevel: Bool { engine.isAvailable && reading.isLevel(tolerance: tolerance) }
    private var tint: Color { isLevel ? .green : .accentColor }

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
        .background(Color.black)
        .onAppear { engine.start() }
        .onDisappear { engine.stop() }
        .sensoryFeedback(.success, trigger: isLevel) { _, new in new }
        .animation(.easeInOut(duration: 0.2), value: isLevel)
        .animation(.snappy, value: reading.isFlat)
        .animation(.snappy, value: showSaved)
    }

    private var content: some View {
        VStack(spacing: 0) {
            Group {
                if showSaved {
                    SavedToast()
                } else {
                    Text(reading.isFlat ? "Lay iPhone on the surface" : "Hold an edge of iPhone against the surface")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
            .frame(height: 44)

            Spacer(minLength: 12)

            Group {
                if reading.isFlat {
                    BubbleGauge(roll: reading.surfaceRoll, pitch: reading.surfacePitch, tint: tint)
                } else {
                    HorizonGauge(deviation: reading.edgeDeviation, tint: tint)
                }
            }
            .frame(width: 280, height: 280)
            .transition(.opacity)

            Text(MeasureFormat.angle(reading.tilt))
                .font(.system(size: 72, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: reading.tilt))
                .foregroundStyle(isLevel ? Color.green : Color.white)
                .padding(.top, 20)

            let hint = reading.hint(tolerance: tolerance)
            Label(hint.text, systemImage: hint.systemImage)
                .font(.headline)
                .foregroundStyle(isLevel ? Color.green : Color.white.opacity(0.85))
                .contentTransition(.symbolEffect(.replace))

            Text(details)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.6))
                .padding(.top, 6)

            Spacer(minLength: 12)

            HStack(spacing: 12) {
                Button {
                    reading.reference == nil ? engine.setReference() : engine.clearReference()
                } label: {
                    Label(reading.reference == nil ? "Set Zero" : "Clear Zero",
                          systemImage: reading.reference == nil ? "scope" : "xmark")
                        .frame(maxWidth: .infinity)
                }
                .levelButtonStyle(prominent: false)

                Button(action: save) {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .levelButtonStyle(prominent: true)
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .padding(.top, 8)
    }

    private var details: String {
        var parts: [String] = []
        if reading.isFlat {
            parts.append("L–R " + MeasureFormat.angle(abs(reading.surfaceRoll)))
            parts.append("F–B " + MeasureFormat.angle(abs(reading.surfacePitch)))
        }
        parts.append(String(format: "Slope %.1f%%", reading.slopePercent))
        if reading.reference != nil { parts.append("from your zero") }
        return parts.joined(separator: "  ·  ")
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

private extension View {
    @ViewBuilder
    func levelButtonStyle(prominent: Bool) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}

/// Dial face shared by both gauges: a subtle disc, a rim and tick marks every 15°.
private struct GaugeFace: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.06))
            Circle().stroke(Color.white.opacity(0.25), lineWidth: 1)
            ForEach(0..<24, id: \.self) { i in
                let major = i % 6 == 0
                Capsule()
                    .fill(Color.white.opacity(major ? 0.8 : 0.35))
                    .frame(width: major ? 3 : 2, height: major ? 14 : 8)
                    .offset(y: -140 + (major ? 11 : 8))
                    .rotationEffect(.degrees(Double(i) * 15))
            }
        }
    }
}

/// Artificial horizon: the tinted half is the ground and stays level with the world while iPhone rotates.
/// The fixed white marks at 3 and 9 o'clock line up with the horizon when level.
private struct HorizonGauge: View {
    let deviation: Double
    let tint: Color

    var body: some View {
        ZStack {
            GaugeFace()

            ZStack {
                Rectangle()
                    .fill(tint.opacity(0.85).gradient)
                    .frame(width: 600, height: 300)
                    .offset(y: 150)
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 600, height: 2)
            }
            .rotationEffect(.degrees(-deviation))
            .clipShape(Circle().inset(by: 1))

            HStack {
                Capsule().fill(Color.white).frame(width: 36, height: 4)
                Spacer()
                Capsule().fill(Color.white).frame(width: 36, height: 4)
            }
            .padding(.horizontal, 6)
            Circle().fill(Color.white).frame(width: 8, height: 8)
        }
        .accessibilityElement()
        .accessibilityLabel(String(format: "Tilted %.1f degrees", abs(deviation)))
    }
}

/// Bubble level: rings at 1°, 5°, 10° and 15°; the bubble floats to the high side.
private struct BubbleGauge: View {
    let roll: Double
    let pitch: Double
    let tint: Color

    private let pointsPerDegree = 8.0
    private let maxDegrees = 15.0

    var body: some View {
        let radius = maxDegrees * pointsPerDegree
        ZStack {
            GaugeFace()
            ForEach([1.0, 5.0, 10.0], id: \.self) { degrees in
                Circle()
                    .stroke(Color.white.opacity(degrees == 1 ? 0.8 : 0.25), lineWidth: degrees == 1 ? 2 : 1)
                    .frame(width: degrees * pointsPerDegree * 2, height: degrees * pointsPerDegree * 2)
            }
            Rectangle().fill(Color.white.opacity(0.2)).frame(width: radius * 2, height: 1)
            Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: radius * 2)

            Circle()
                .fill(tint.gradient)
                .frame(width: 36, height: 36)
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
                .shadow(color: .black.opacity(0.4), radius: 6)
                .offset(bubbleOffset(radius: radius))
                .animation(.interactiveSpring(response: 0.25), value: roll)
                .animation(.interactiveSpring(response: 0.25), value: pitch)
        }
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
