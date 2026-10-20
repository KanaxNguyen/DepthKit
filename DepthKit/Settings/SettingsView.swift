import AppIntents
import SwiftUI

struct SettingsView: View {
    @AppStorage(SharedSettings.unitsKey, store: AppGroup.defaults) private var units: UnitSystem = .metric
    @AppStorage(SharedSettings.divisorKey, store: AppGroup.defaults) private var divisor: Double = 5000

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Units", selection: $units) {
                        ForEach(UnitSystem.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    Picker("Divisor", selection: $divisor) {
                        Text("5000 (most couriers)").tag(5000.0)
                        Text("6000").tag(6000.0)
                    }
                } header: {
                    Text("Dimensional Weight")
                } footer: {
                    Text("Length × Width × Height in cm³, divided by the courier's divisor, gives the weight couriers charge for bulky parcels.")
                }

                Section {
                    SiriTipView(intent: StartMeasurementIntent(mode: .box))
                    ShortcutsLink()
                } header: {
                    Text("Siri & Shortcuts")
                } footer: {
                    Text("Try “Measure a box with DepthKit” or “What was my last measurement in DepthKit”. Add the Measure Box control in Control Center and the widget on your Home Screen.")
                }

                Section("Sensors on This iPhone") {
                    LabeledContent("LiDAR Scanner", value: ARMeasureEngine.isSupported ? "Available" : "Not available")
                    LabeledContent("TrueDepth Camera", value: TrueDepthEngine.isSupported ? "Available" : "Not available")
                }

                Section {
                    NavigationLink {
                        DeveloperView()
                    } label: {
                        Label("Developer", systemImage: "hammer")
                    }
                } footer: {
                    Text("Tune the measuring algorithms, show depth overlays and capture RGB + depth samples.")
                }

                Section {
                    Text("DepthKit estimates sizes from depth sensors; results can be off by a centimeter or more. Check anything critical with a tape measure. Camera images are processed on device and never uploaded. They are saved only when you capture a sample in Developer mode.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
