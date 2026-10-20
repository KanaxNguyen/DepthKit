import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @Environment(HistoryModel.self) private var history
    @AppStorage(SharedSettings.unitsKey, store: AppGroup.defaults) private var units: UnitSystem = .metric
    @AppStorage(SharedSettings.divisorKey, store: AppGroup.defaults) private var divisor: Double = 5000
    @State private var confirmDeleteAll = false

    var body: some View {
        NavigationStack {
            Group {
                if history.records.isEmpty {
                    ContentUnavailableView {
                        Label("No Measurements", systemImage: "ruler")
                    } description: {
                        Text("Results you save appear here and in the DepthKit widget.")
                    }
                } else {
                    List {
                        ForEach(history.records) { record in
                            HistoryRow(record: record, units: units, divisor: divisor)
                        }
                        .onDelete { history.delete(at: $0) }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !history.records.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear", role: .destructive) { confirmDeleteAll = true }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: CSVFile(text: CSVExport.make(history.records, units: units)),
                                  preview: SharePreview("DepthKit Measurements", image: Image(systemName: "tablecells")))
                    }
                }
            }
            .confirmationDialog("Delete all measurements?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) { history.deleteAll() }
            } message: {
                Text("This can't be undone.")
            }
        }
    }
}

private struct HistoryRow: View {
    let record: MeasurementRecord
    let units: UnitSystem
    let divisor: Double

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: record.mode.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(MeasureFormat.summary(record, units: units))
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(record.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        if record.mode == .box {
            return String(format: "%.1f L · %.1f kg dim. weight", DimensionalWeight.liters(record.values),
                          DimensionalWeight.kilograms(record.values, divisor: divisor))
        }
        return "\(record.mode.title) · \(record.mode.sensor)"
    }
}

struct CSVFile: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data($0.text.utf8) }
            .suggestedFileName("DepthKit Measurements.csv")
    }
}
