import SwiftUI

struct MeasureView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            Group {
                // LiDAR modes share one view so switching between them keeps the AR session running.
                if router.mode.usesLiDAR {
                    LiDARMeasureView(mode: router.mode)
                } else if router.mode == .near {
                    TrueDepthMeasureView()
                } else {
                    LevelView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ModeSwitcher(selection: $router.mode)
                .padding(.bottom, 12)
        }
        .background(Color.black)
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

/// Explains why a mode can't run here and points to the modes that can.
struct SensorUnavailableView: View {
    let title: String
    let message: String

    private var alternatives: String {
        var modes: [String] = []
        if ARMeasureEngine.isSupported { modes += ["Distance", "Range", "Box"] }
        if TrueDepthEngine.isSupported { modes.append("Near") }
        if LevelEngine.isSupported { modes.append("Level") }
        guard !modes.isEmpty else { return "This device has no depth or motion sensors. Try DepthKit on an iPhone." }
        return "Available here: " + ListFormatter.localizedString(byJoining: modes) + "."
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "sensor")
        } description: {
            Text(message + "\n\n" + alternatives)
        }
        .foregroundStyle(.white)
        .padding(.bottom, 80)
    }
}
