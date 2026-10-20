import AppIntents
import SwiftUI
import WidgetKit

@main
struct DepthKitWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecentMeasurementsWidget()
        MeasureBoxControl()
        MeasureDistanceControl()
    }
}

// MARK: - Recent measurements widget

struct RecentEntry: TimelineEntry {
    let date: Date
    let records: [MeasurementRecord]
    let units: UnitSystem

    static let sample = RecentEntry(date: .now, records: [
        MeasurementRecord(mode: .box, values: [0.42, 0.31, 0.25]),
        MeasurementRecord(date: .now.addingTimeInterval(-3600), mode: .distance, values: [1.84]),
        MeasurementRecord(date: .now.addingTimeInterval(-7200), mode: .level, values: [0.4]),
    ], units: .metric)
}

struct RecentProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (RecentEntry) -> Void) {
        completion(context.isPreview ? .sample : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentEntry>) -> Void) {
        // The app reloads timelines whenever it saves, so no refresh schedule is needed.
        completion(Timeline(entries: [current()], policy: .never))
    }

    private func current() -> RecentEntry {
        let records = MeasurementStore.shared.load().sorted { $0.date > $1.date }
        return RecentEntry(date: .now, records: Array(records.prefix(3)), units: SharedSettings.units)
    }
}

struct RecentMeasurementsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecentMeasurements", provider: RecentProvider()) { entry in
            RecentWidgetView(entry: entry)
        }
        .configurationDisplayName("Recent Measurements")
        .description("Your latest DepthKit results, with shortcuts to start measuring.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct RecentWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecentEntry

    private var latest: MeasurementRecord? { entry.records.first }

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(URL(string: "depthkit://measure/\((latest?.mode ?? .box).rawValue)"))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            if let latest {
                Label(MeasureFormat.summary(latest, units: entry.units), systemImage: latest.mode.systemImage)
            } else {
                Label("DepthKit", systemImage: "ruler")
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("DepthKit", systemImage: latest?.mode.systemImage ?? "ruler")
                    .font(.headline)
                    .widgetAccentable()
                Text(latest.map { MeasureFormat.summary($0, units: entry.units) } ?? "No measurements")
                    .font(.body.monospacedDigit())
                    .minimumScaleFactor(0.6)
                if let latest {
                    Text(latest.date, style: .relative).font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if entry.records.isEmpty {
                        Text("No measurements yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(entry.records) { record in
                        HStack(spacing: 8) {
                            Image(systemName: record.mode.systemImage)
                                .foregroundStyle(.tint)
                                .frame(width: 20)
                            Text(MeasureFormat.summary(record, units: entry.units))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 8) {
                    QuickStart(mode: .box)
                    QuickStart(mode: .distance)
                }
                .frame(width: 96)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Label("DepthKit", systemImage: "ruler")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let latest {
                    Image(systemName: latest.mode.systemImage)
                        .font(.title2)
                        .foregroundStyle(.tint)
                    Text(MeasureFormat.summary(latest, units: entry.units))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .minimumScaleFactor(0.5)
                        .lineLimit(2)
                    Text(latest.date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tap to measure")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct QuickStart: View {
    let mode: MeasureMode

    var body: some View {
        Link(destination: URL(string: "depthkit://measure/\(mode.rawValue)")!) {
            VStack(spacing: 4) {
                Image(systemName: mode.systemImage).font(.title3)
                Text(mode == .box ? "Box" : "Distance").font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityLabel(mode == .box ? "Measure a box" : "Measure distance")
    }
}

// MARK: - Control Center controls

struct MeasureBoxControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "vn.kanax.depthkit.control.box") {
            ControlWidgetButton(action: StartMeasurementIntent(mode: .box)) {
                Label("Measure Box", systemImage: "shippingbox")
            }
        }
        .displayName("Measure Box")
        .description("Open DepthKit ready to measure a box.")
    }
}

struct MeasureDistanceControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "vn.kanax.depthkit.control.distance") {
            ControlWidgetButton(action: StartMeasurementIntent(mode: .distance)) {
                Label("Measure Distance", systemImage: "ruler")
            }
        }
        .displayName("Measure Distance")
        .description("Open DepthKit ready to measure a distance.")
    }
}

#Preview(as: .systemMedium) {
    RecentMeasurementsWidget()
} timeline: {
    RecentEntry.sample
}
