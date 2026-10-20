import XCTest
import simd
@testable import DepthKit

/// Renders a synthetic depth map of a box on the floor, seen straight down from `cameraHeight`,
/// and checks that the estimator recovers its size.
final class BoxEstimatorTests: XCTestCase {
    private let width = 256, height = 192
    private let focal: Float = 200

    private func renderBox(length: Float, width boxWidth: Float, height boxHeight: Float,
                           yawDegrees: Float = 0, cameraHeight: Float = 1.2) -> DepthFrame {
        // Camera at (0, cameraHeight, 0) looking down: camera x → world x, camera y → world -z, camera z → world y.
        let cameraToWorld = simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0), SIMD4(0, 0, -1, 0), SIMD4(0, 1, 0, 0), SIMD4(0, cameraHeight, 0, 1)
        ))
        let k = simd_float3x3(columns: (SIMD3(focal, 0, 0), SIMD3(0, focal, 0), SIMD3(Float(width) / 2, Float(height) / 2, 1)))
        let yaw = yawDegrees * .pi / 180

        var depth = [Float](repeating: cameraHeight, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let rx = (Float(x) - Float(width) / 2) / focal
                let ry = -(Float(y) - Float(height) / 2) / focal
                // Ray in world: (rx, -1, -ry) per unit of depth. Hit the top face at y = boxHeight.
                let t = cameraHeight - boxHeight
                let wx = rx * t, wz = -ry * t
                // Rotate into the box's frame.
                let bx = cos(-yaw) * wx - sin(-yaw) * wz
                let bz = sin(-yaw) * wx + cos(-yaw) * wz
                if abs(bx) <= length / 2, abs(bz) <= boxWidth / 2 { depth[y * width + x] = t }
            }
        }
        return DepthFrame(width: width, height: height, depth: depth, confidence: nil,
                          intrinsics: k, cameraToWorld: cameraToWorld)
    }

    func testRecoversAxisAlignedBox() throws {
        let frame = renderBox(length: 0.40, width: 0.30, height: 0.25)
        let box = try XCTUnwrap(BoxEstimator.estimate(frame, floorY: 0))
        XCTAssertEqual(box.length, 0.40, accuracy: 0.015)
        XCTAssertEqual(box.width, 0.30, accuracy: 0.015)
        XCTAssertEqual(box.height, 0.25, accuracy: 0.005)
    }

    func testRecoversRotatedBox() throws {
        let frame = renderBox(length: 0.35, width: 0.20, height: 0.15, yawDegrees: 35)
        let box = try XCTUnwrap(BoxEstimator.estimate(frame, floorY: 0))
        XCTAssertEqual(box.length, 0.35, accuracy: 0.015)
        XCTAssertEqual(box.width, 0.20, accuracy: 0.015)
        XCTAssertEqual(box.height, 0.15, accuracy: 0.005)
        XCTAssertEqual(box.corners.count, 8)
    }

    func testEmptyFloorFindsNothing() {
        let frame = renderBox(length: 0, width: 0, height: 0.0)
        XCTAssertNil(BoxEstimator.estimate(frame, floorY: 0))
    }

    func testCombineUsesMedians() throws {
        let a = BoxEstimate(length: 0.40, width: 0.30, height: 0.20, footprint: [], floorY: 0)
        let b = BoxEstimate(length: 0.42, width: 0.31, height: 0.21, footprint: [], floorY: 0)
        let c = BoxEstimate(length: 0.90, width: 0.29, height: 0.22, footprint: [], floorY: 0)
        let combined = try XCTUnwrap(BoxEstimator.combine([a, b, c]))
        XCTAssertEqual(combined.length, 0.42, accuracy: 1e-9)
        XCTAssertEqual(combined.width, 0.30, accuracy: 1e-9)
        XCTAssertEqual(combined.height, 0.21, accuracy: 1e-9)
    }
}
