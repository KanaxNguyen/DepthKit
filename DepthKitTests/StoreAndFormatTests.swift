import XCTest
@testable import DepthKit

final class StoreAndFormatTests: XCTestCase {
    func testStoreRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MeasurementStore(directory: directory)
        XCTAssertTrue(store.load().isEmpty)

        let older = MeasurementRecord(date: Date(timeIntervalSince1970: 100), mode: .distance, values: [1.5])
        let newer = MeasurementRecord(date: Date(timeIntervalSince1970: 200), mode: .box, values: [0.4, 0.3, 0.2])
        try store.save([older, newer])

        XCTAssertEqual(store.load(), [older, newer])
        XCTAssertEqual(store.latest, newer)
    }

    func testLengthFormatting() {
        XCTAssertEqual(MeasureFormat.length(0.456, units: .metric), "45.6 cm")
        XCTAssertEqual(MeasureFormat.length(1.234, units: .metric), "1.23 m")
        XCTAssertEqual(MeasureFormat.length(0.254, units: .imperial), "10.0 in")
        XCTAssertEqual(MeasureFormat.length(1.6, units: .imperial), "5 ft 3.0 in")
    }

    func testBoxFormattingAndDimensionalWeight() {
        let dims = [0.40, 0.30, 0.25]
        XCTAssertEqual(MeasureFormat.box(dims, units: .metric), "40.0 × 30.0 × 25.0 cm")
        XCTAssertEqual(DimensionalWeight.liters(dims), 30, accuracy: 1e-9)
        XCTAssertEqual(DimensionalWeight.kilograms(dims, divisor: 5000), 6, accuracy: 1e-9)
        XCTAssertEqual(DimensionalWeight.kilograms(dims, divisor: 6000), 5, accuracy: 1e-9)
    }

    func testSpokenSummary() {
        let record = MeasurementRecord(mode: .box, values: [0.4, 0.3, 0.25])
        XCTAssertEqual(MeasureFormat.spoken(record, units: .metric), "Your last box measured 40.0 × 30.0 × 25.0 cm.")
    }

    func testCSVHasHeaderAndPadsValues() {
        let csv = CSVExport.make([MeasurementRecord(mode: .range, values: [2])], units: .metric)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.first, "date,mode,sensor,value1,value2,value3,unit,summary")
        XCTAssertTrue(lines[1].contains(",range,LiDAR,2.0000,,,m,\"2.00 m\""))
    }

    func testRouterMergesDistanceModesIntoOneTool() {
        let router = AppRouter()
        router.open(.near)
        XCTAssertEqual(router.tool, .distance)
        XCTAssertEqual(router.distanceMethod, .fromPhone)
        XCTAssertEqual(router.mode, .near)
        router.distanceSensor = .lidar
        XCTAssertEqual(router.mode, .range)
        router.distanceMethod = .twoPoints
        XCTAssertEqual(router.mode, .distance)
        router.tool = .level
        XCTAssertEqual(router.mode, .level)
    }

    func testRouterHandlesDeepLinks() {
        let router = AppRouter()
        router.tab = .settings
        router.handle(url: URL(string: "depthkit://measure/box")!)
        XCTAssertEqual(router.tab, .measure)
        XCTAssertEqual(router.mode, .box)
        router.handle(url: URL(string: "depthkit://history")!)
        XCTAssertEqual(router.tab, .history)
    }
}
