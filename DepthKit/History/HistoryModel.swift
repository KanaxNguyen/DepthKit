import Foundation
import Observation
import WidgetKit

@Observable
final class HistoryModel {
    private(set) var records: [MeasurementRecord] = []
    @ObservationIgnored private let store: MeasurementStore

    init(store: MeasurementStore = .shared) {
        self.store = store
        reload()
    }

    func reload() {
        records = store.load().sorted { $0.date > $1.date }
    }

    func add(_ record: MeasurementRecord) {
        records.insert(record, at: 0)
        persist()
    }

    func delete(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        persist()
    }

    func deleteAll() {
        records.removeAll()
        persist()
    }

    private func persist() {
        try? store.save(records)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

enum CSVExport {
    static func make(_ records: [MeasurementRecord], units: UnitSystem) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["date,mode,sensor,value1,value2,value3,unit,summary"]
        for record in records {
            var values = record.values.map { String(format: "%.4f", $0) }
            while values.count < 3 { values.append("") }
            let unit = record.mode == .level ? "deg" : "m"
            let summary = MeasureFormat.summary(record, units: units).replacingOccurrences(of: "\"", with: "\"\"")
            lines.append([formatter.string(from: record.date), record.mode.rawValue, record.mode.sensor,
                          values[0], values[1], values[2], unit, "\"\(summary)\""].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
