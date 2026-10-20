import AppIntents

/// Phrases Siri understands without any setup. Each must contain the app name.
struct DepthKitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartMeasurementIntent(mode: .box),
            phrases: [
                "Measure a box with \(.applicationName)",
                "Measure a package with \(.applicationName)",
            ],
            shortTitle: "Measure Box",
            systemImageName: "shippingbox"
        )
        AppShortcut(
            intent: StartMeasurementIntent(mode: .distance),
            phrases: [
                "Measure distance with \(.applicationName)",
                "Start \(.applicationName)",
            ],
            shortTitle: "Measure Distance",
            systemImageName: "ruler"
        )
        AppShortcut(
            intent: StartMeasurementIntent(mode: .level),
            phrases: ["Open the level in \(.applicationName)"],
            shortTitle: "Level",
            systemImageName: "level"
        )
        AppShortcut(
            intent: LastMeasurementIntent(),
            phrases: [
                "What was my last measurement in \(.applicationName)",
                "Last measurement in \(.applicationName)",
            ],
            shortTitle: "Last Measurement",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}
