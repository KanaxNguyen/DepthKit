import XCTest
import simd
@testable import DepthKit

final class GeometryTests: XCTestCase {
    func testHullDropsInteriorPoints() {
        let square: [SIMD2<Double>] = [[0, 0], [1, 0], [1, 1], [0, 1]]
        let hull = Geometry.convexHull(square + [[0.5, 0.5], [0.2, 0.7], [0.5, 0]])
        XCTAssertEqual(Set(hull.map { "\($0.x),\($0.y)" }), Set(square.map { "\($0.x),\($0.y)" }))
    }

    func testMinAreaRectFindsRotatedRectangle() throws {
        let angle = 30.0 * .pi / 180
        let rotation = simd_double2x2(SIMD2(cos(angle), sin(angle)), SIMD2(-sin(angle), cos(angle)))
        var points: [SIMD2<Double>] = []
        for i in 0...20 {
            for j in 0...10 {
                points.append(rotation * SIMD2(Double(i) * 0.02, Double(j) * 0.03) + SIMD2(5, -2))
            }
        }
        let rect = try XCTUnwrap(Geometry.minAreaRect(points))
        XCTAssertEqual(rect.length, 0.4, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 0.3, accuracy: 1e-9)
    }

    func testMinAreaRectNeedsThreePoints() {
        XCTAssertNil(Geometry.minAreaRect([[0, 0], [1, 1]]))
    }

    func testPercentileInterpolates() {
        XCTAssertEqual(Geometry.percentile([1, 2, 3, 4], 0.5), 2.5)
        XCTAssertEqual(Geometry.percentile([5], 0.9), 5)
        XCTAssertNil(Geometry.median([]))
    }

    func testCenterMedianSkipsLowConfidenceAndEmptyPixels() {
        let width = 5, height = 5
        var depth = [Float](repeating: 1.0, count: width * height)
        var confidence = [UInt8](repeating: 2, count: width * height)
        depth[12] = 0              // center pixel: no data
        depth[11] = 9; confidence[11] = 0   // outlier with low confidence
        let value = PixelBuffers.centerMedian(depth: depth, width: width, height: height,
                                              confidence: confidence, minConfidence: 1, window: 3)
        XCTAssertEqual(value, 1.0)
    }

    func testLevelReading() {
        let upright = LevelEngine.reading(gx: 0, gy: -1, gz: 0)
        XCTAssertFalse(upright.isFlat)
        XCTAssertEqual(upright.primary, 0, accuracy: 1e-9)

        let tilted = LevelEngine.reading(gx: sin(.pi / 18), gy: -cos(.pi / 18), gz: 0)
        XCTAssertEqual(tilted.primary, 10, accuracy: 1e-6)

        let flat = LevelEngine.reading(gx: 0, gy: 0, gz: -1)
        XCTAssertTrue(flat.isFlat)
    }
}
