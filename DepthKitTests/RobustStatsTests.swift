import XCTest
import simd
@testable import DepthKit

final class RobustStatsTests: XCTestCase {
    func testConfidenceIntervalMatchesStudentT() throws {
        let e = try XCTUnwrap(RobustStats.estimate([2.0, 2.1, 1.9, 2.0, 2.0]))
        XCTAssertEqual(e.value, 2.0, accuracy: 1e-12)
        // sd = 0.0707, se = 0.0316, t(4) = 2.776 -> 0.0878
        XCTAssertEqual(e.margin ?? 0, 0.0878, accuracy: 1e-4)
        XCTAssertEqual(e.count, 5)
    }

    func testOutlierFromAShakeIsRejected() throws {
        let e = try XCTUnwrap(RobustStats.estimate([1.00, 1.01, 0.99, 1.00, 1.02, 3.5]))
        XCTAssertEqual(e.rejected, 1)
        XCTAssertEqual(e.value, 1.004, accuracy: 1e-9)
    }

    func testSingleReadingHasNoInterval() throws {
        let e = try XCTUnwrap(RobustStats.estimate([1.5, .nan]))
        XCTAssertNil(e.margin)
        XCTAssertNil(RobustStats.estimate([]))
    }

    func testOverlap() {
        let a = Estimate(value: 1.95, margin: 0.03, count: 5)
        XCTAssertTrue(a.overlaps(Estimate(value: 1.99, margin: 0.02, count: 5)))
        XCTAssertFalse(a.overlaps(Estimate(value: 2.10, margin: 0.02, count: 5)))
    }

    func testMedianStackIgnoresMissingPixels() {
        let merged = RobustStats.medianStack([[1, .nan, 3], [2, 5, 0], [9, .nan, 4]])
        XCTAssertEqual(merged[0], 2)
        XCTAssertEqual(merged[1], 5)
        XCTAssertEqual(merged[2], 3.5)
    }

    func testRollingWindowRestartsOnNewTarget() {
        var window = RollingWindow(capacity: 4)
        [1.0, 1.01, 0.99, 1.0, 1.02].forEach { window.add($0) }
        XCTAssertEqual(window.samples.count, 4)
        window.add(2.5)                      // aimed at something else
        XCTAssertEqual(window.samples, [2.5])
    }

    func testMedianPointResistsAJerk() throws {
        let samples: [SIMD3<Float>] = [[0, 0, 1], [0.001, 0, 1], [0, 0.001, 1.001], [0.2, 0.1, 0.8], [0, 0, 1]]
        let p = try XCTUnwrap(ARMeasureEngine.medianPoint(samples))
        XCTAssertEqual(p.x, 0, accuracy: 0.002)
        XCTAssertEqual(p.z, 1, accuracy: 0.002)
    }

    func testTargetBeyondStereoRangeIsExplainedNotScored() {
        // Real capture: LiDAR 3.56 m, Apple stereo tops out near 1.65 m.
        let lidar = [Float](repeating: 3.56, count: 16 * 12)
        var stereo = [Float](repeating: 1.52, count: 16 * 12)
        stereo[0] = 1.65
        let c = SensorComparison.compute(lidar: lidar, lidarSize: (16, 12), stereo: stereo, stereoSize: (16, 12), brightness: 0.5)
        XCTAssertTrue(c.isBeyondStereoRange)
        XCTAssertTrue(c.verdict.hasPrefix("Beyond the two-camera range"))

        let near = SensorComparison.compute(lidar: [Float](repeating: 1.97, count: 16 * 12), lidarSize: (16, 12),
                                            stereo: [Float](repeating: 1.92, count: 16 * 12), stereoSize: (16, 12), brightness: 0.5)
        XCTAssertFalse(near.isBeyondStereoRange)
    }

    func testCompareUsesShotIntervals() {
        let lidar = [Float](repeating: 1.97, count: 16 * 12)
        let stereo = [Float](repeating: 1.92, count: 16 * 12)
        let c = SensorComparison.compute(lidar: lidar, lidarSize: (16, 12), stereo: stereo, stereoSize: (16, 12),
                                         brightness: 0.5, lidarCenters: [1.97, 1.96, 1.98, 1.97, 1.97],
                                         stereoCenters: [1.90, 1.95, 1.93, 1.89, 1.94], shake: 0.05)
        XCTAssertEqual(c.lidarEstimate?.count, 5)
        XCTAssertNotNil(c.stereoEstimate?.margin)
        XCTAssertEqual(c.stereoCenter ?? 0, 1.922, accuracy: 1e-9)
        XCTAssertEqual(MotionMonitor.describe(c.shake ?? 1), "Very steady")
    }
}
