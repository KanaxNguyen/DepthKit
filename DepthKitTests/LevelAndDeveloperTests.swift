import XCTest
@testable import DepthKit

final class LevelTests: XCTestCase {
    private func degrees(_ d: Double) -> Double { d * .pi / 180 }

    func testEdgeAnglesFromGravity() {
        let upright = LevelReading.angles(gx: 0, gy: -1, gz: 0, wasFlat: false)
        XCTAssertFalse(upright.isFlat)
        XCTAssertEqual(upright.edge, 0, accuracy: 1e-9)

        // Turned 10° clockwise: gravity tilts toward +x in device coordinates.
        let turned = LevelReading.angles(gx: sin(degrees(10)), gy: -cos(degrees(10)), gz: 0, wasFlat: false)
        XCTAssertEqual(turned.edge, 10, accuracy: 1e-9)
    }

    func testFlatHysteresis() {
        XCTAssertTrue(LevelReading.angles(gx: 0, gy: 0, gz: -1, wasFlat: false).isFlat)
        // |gz| = 0.75 sits between the thresholds: keeps the previous mode.
        XCTAssertTrue(LevelReading.angles(gx: 0, gy: -0.66, gz: -0.75, wasFlat: true).isFlat)
        XCTAssertFalse(LevelReading.angles(gx: 0, gy: -0.66, gz: -0.75, wasFlat: false).isFlat)
    }

    func testEdgeDeviationSnapsToNearestRightAngle() {
        XCTAssertEqual(LevelReading(edgeAngle: 92).edgeDeviation, 2, accuracy: 1e-9)
        XCTAssertEqual(LevelReading(edgeAngle: -88).edgeDeviation, 2, accuracy: 1e-9)
        XCTAssertEqual(LevelReading(edgeAngle: 3).edgeDeviation, 3, accuracy: 1e-9)
    }

    func testReferenceMeasuresRelativeAngle() {
        var reading = LevelReading(edgeAngle: 30, reference: .edge(25))
        XCTAssertEqual(reading.edgeDeviation, 5, accuracy: 1e-9)
        reading = LevelReading(isFlat: true, roll: 4, pitch: -1, reference: .surface(roll: 3, pitch: -1))
        XCTAssertEqual(reading.surfaceRoll, 1, accuracy: 1e-9)
        XCTAssertEqual(reading.surfacePitch, 0, accuracy: 1e-9)
    }

    func testHintsPointTheRightWay() {
        XCTAssertEqual(LevelReading(edgeAngle: 4).hint(tolerance: 0.5).text, "Rotate counterclockwise")
        XCTAssertEqual(LevelReading(edgeAngle: -4).hint(tolerance: 0.5).text, "Rotate clockwise")
        XCTAssertEqual(LevelReading(edgeAngle: 0.2).hint(tolerance: 0.5).text, "Level")
        XCTAssertEqual(LevelReading(isFlat: true, roll: 3, pitch: 1).hint(tolerance: 0.5).text, "Raise the right side")
        XCTAssertEqual(LevelReading(isFlat: true, roll: 0.5, pitch: -2).hint(tolerance: 0.5).text, "Raise the bottom edge")
    }

    func testSlopePercent() {
        XCTAssertEqual(LevelReading(edgeAngle: 45).slopePercent, 100, accuracy: 1e-9)
        XCTAssertEqual(LevelReading(isFlat: true, roll: 0, pitch: 0).slopePercent, 0, accuracy: 1e-9)
    }
}

final class DeveloperToolsTests: XCTestCase {
    override func tearDown() {
        DevSettings.resetToDefaults()
        super.tearDown()
    }

    func testBoxOptionsFollowSettings() {
        XCTAssertEqual(DevSettings.boxOptions.minHeight, 0.02, accuracy: 1e-6)
        AppGroup.defaults.set(4.0, forKey: DevSettings.Key.boxMinHeightCm)
        AppGroup.defaults.set(1, forKey: DevSettings.Key.boxMinConfidence)
        AppGroup.defaults.set(0.9, forKey: DevSettings.Key.boxHeightPercentile)
        let options = DevSettings.boxOptions
        XCTAssertEqual(options.minHeight, 0.04, accuracy: 1e-6)
        XCTAssertEqual(options.minConfidence, 1)
        XCTAssertEqual(options.heightPercentile, 0.9, accuracy: 1e-9)
        DevSettings.resetToDefaults()
        XCTAssertEqual(DevSettings.boxOptions.minHeight, 0.02, accuracy: 1e-6)
    }

    func testDepthStats() {
        let stats = DepthStats.compute(depth: [1, 2, 0, .nan], confidence: [2, 1, 2, 2])
        XCTAssertEqual(stats.validFraction, 0.5)
        XCTAssertEqual(stats.highConfidenceFraction, 0.25)
        XCTAssertEqual(stats.minDepth, 1)
        XCTAssertEqual(stats.maxDepth, 2)
    }

    func testColormapNearIsRedFarIsBlue() {
        let near = DepthColormap.turbo(0)
        let far = DepthColormap.turbo(1)
        XCTAssertGreaterThan(near.0, near.2)
        XCTAssertGreaterThan(far.2, far.0)
        let pixels = DepthColormap.rgba(depth: [1, 0], confidence: nil, highlight: [0])
        XCTAssertEqual(Array(pixels[0..<4]), [255, 255, 255, 255])
        XCTAssertEqual(pixels[7], 0, "pixels without depth stay transparent")
    }

    func testDatasetWriterLayout() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sample = DatasetSample(timestamp: Date(timeIntervalSince1970: 1_000_000), device: "iPhone16,2", mode: "range",
                                   imageWidth: 1920, imageHeight: 1440, depthWidth: 2, depthHeight: 1,
                                   intrinsics: [1, 0, 0, 0, 1, 0, 0, 0, 1], cameraToWorld: Array(repeating: 0, count: 16),
                                   floorY: -1.2)
        let folder = try DatasetWriter.save(sample: sample, rgbJPEG: Data([0xFF, 0xD8]), depth: [1.5, 2.5],
                                            confidence: [2, 0], preview: nil, root: root)

        let depth = try Data(contentsOf: folder.appendingPathComponent("depth.f32"))
        XCTAssertEqual(depth.count, 8)
        XCTAssertEqual(depth.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }, [1.5, 2.5])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("confidence.u8")), Data([2, 0]))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let meta = try decoder.decode(DatasetSample.self, from: Data(contentsOf: folder.appendingPathComponent("meta.json")))
        XCTAssertEqual(meta, sample)
        XCTAssertEqual(DatasetWriter.summary(root: root).count, 1)
    }
}
