import SwiftUI

extension View {
    /// Liquid Glass on iOS 26 and later, a system material before that.
    @ViewBuilder
    func hudBackground<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}

/// Large readout card floating over the camera.
struct ReadoutCard<Detail: View>: View {
    let title: String
    let value: String?
    var placeholder = "—"
    @ViewBuilder var detail: Detail

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value ?? placeholder)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            detail
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .hudBackground(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Short instruction pill at the top of the camera view.
struct HintPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout.weight(.medium))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .hudBackground(in: Capsule())
    }
}

/// Round control button used in the measuring toolbar.
struct HUDButton: View {
    let title: String
    let systemImage: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .frame(width: prominent ? 72 : 56, height: prominent ? 72 : 56)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .background {
                    if prominent { Circle().fill(Color.accentColor) }
                }
                .hudBackground(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct Crosshair: View {
    var body: some View {
        ZStack {
            Circle().stroke(.white, lineWidth: 2).frame(width: 28, height: 28)
            Circle().fill(.white).frame(width: 4, height: 4)
        }
        .shadow(color: .black.opacity(0.4), radius: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Camera-style tool switcher.
struct ModeSwitcher: View {
    @Binding var selection: MeasureTool
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MeasureTool.allCases) { mode in
                Button {
                    withAnimation(.snappy) { selection = mode }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: mode.systemImage)
                            .font(.body.weight(.semibold))
                            .frame(height: 22)
                        Text(mode.title).font(.caption2.weight(.semibold))
                    }
                    .frame(width: 84, height: 48)
                    .foregroundStyle(selection == mode ? Color.white : Color.primary)
                    .background {
                        if selection == mode {
                            Capsule().fill(Color.accentColor).matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        }
        .padding(5)
        .hudBackground(in: Capsule())
    }
}
