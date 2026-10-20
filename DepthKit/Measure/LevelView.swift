import SwiftUI

struct LevelView: View {
    @Environment(HistoryModel.self) private var history
    @State private var engine = LevelEngine()
    @State private var showSaved = false

    private var isLevel: Bool { abs(engine.primary) < 0.5 && abs(engine.secondary) < 0.5 }

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
        .background(isLevel ? Color.green.gradient : Color.black.gradient)
        .onAppear { engine.start() }
        .onDisappear { engine.stop() }
        .sensoryFeedback(.success, trigger: isLevel) { _, new in new }
        .animation(.snappy, value: showSaved)
    }

    private var content: some View {
        VStack(spacing: 24) {
            if showSaved { SavedToast() } else { HintPill(text: engine.isFlat ? "Lay iPhone on the surface" : "Hold an edge against the surface") }
            Spacer()
            ZStack {
                Circle().stroke(.white.opacity(0.5), lineWidth: 2).frame(width: 220, height: 220)
                Circle().stroke(.white.opacity(0.8), lineWidth: 2).frame(width: 44, height: 44)
                Circle()
                    .fill(.white)
                    .frame(width: 36, height: 36)
                    .offset(bubbleOffset)
                    .animation(.interactiveSpring, value: bubbleOffset)
            }
            .accessibilityHidden(true)
            Text(MeasureFormat.angle(abs(engine.primary)))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            if engine.isFlat {
                Text("Front–back \(MeasureFormat.angle(abs(engine.secondary)))")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            HUDButton(title: "Save", systemImage: "square.and.arrow.down", prominent: true) { save() }
                .padding(.bottom, 84)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var bubbleOffset: CGSize {
        let scale = 4.0, limit = 90.0
        let x = engine.isFlat ? engine.primary * scale : sin(engine.primary * .pi / 180) * limit
        let y = engine.isFlat ? -engine.secondary * scale : 0
        return CGSize(width: max(-limit, min(limit, x)), height: max(-limit, min(limit, y)))
    }

    private func save() {
        history.add(MeasurementRecord(mode: .level, values: [abs(engine.primary)]))
        showSaved = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showSaved = false
        }
    }
}
