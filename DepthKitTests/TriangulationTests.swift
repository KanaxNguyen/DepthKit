import XCTest
import simd
@testable import DepthKit

/// Synthetic scenes: a textured wall seen from two poses, like sliding the iPhone sideways.
final class TriangulationTests: XCTestCase {
    private let width = 640, height = 480
    private let focal = 480.0

    private var intrinsics: simd_double3x3 {
        simd_double3x3(columns: (SIMD3(focal, 0, 0), SIMD3(0, focal, 0),
                                 SIMD3(Double(width - 1) / 2, Double(height - 1) / 2, 1)))
    }

    /// Pose at `position`, turned by `yawDegrees` about the vertical axis.
    private func pose(_ position: SIMD3<Double>, yawDegrees: Double = 0) -> simd_double4x4 {
        let a = yawDegrees * .pi / 180
        return simd_double4x4(columns: (SIMD4(cos(a), 0, -sin(a), 0), SIMD4(0, 1, 0, 0),
                                        SIMD4(sin(a), 0, cos(a), 0), SIMD4(position, 1)))
    }

    private func texture(_ x: Double, _ y: Double) -> Float {
        var value = 128.0
        let waves: [(Double, Double, Double)] = [(23, 7, 0.3), (-11, 31, 1.1), (41, -17, 2.0), (5, 53, 0.7),
                                                 (37, 29, 1.9), (-47, 13, 2.6), (17, -43, 0.1), (59, 3, 1.4)]
        for (fx, fy, phase) in waves { value += 14 * sin(fx * x + fy * y + phase) }
        return Float(min(255, max(0, value)))
    }

    /// Image of the wall z = -distance (or a flat gray wall) from a camera pose.
    private func render(_ cameraToWorld: simd_double4x4, wall distance: Double, flat: Bool = false) -> CameraView {
        var view = CameraView(image: GrayImage(width: width, height: height, pixels: []),
                              intrinsics: intrinsics, cameraToWorld: cameraToWorld)
        var pixels = [Float](repeating: 0, count: width * height)
        let origin = view.center
        for y in 0..<height {
            for x in 0..<width {
                let d = view.ray(through: SIMD2(Double(x), Double(y)))
                let s = (-distance - origin.z) / d.z
                let p = origin + d * s
                pixels[y * width + x] = flat ? 128 : texture(p.x, p.y)
            }
        }
        view.image = GrayImage(width: width, height: height, pixels: pixels)
        return view
    }

    private var center: SIMD2<Double> { SIMD2(Double(width - 1) / 2, Double(height - 1) / 2) }

    func testProjectIsInverseOfRay() {
        let view = CameraView(image: GrayImage(width: 1, height: 1, pixels: [0]), intrinsics: intrinsics,
                              cameraToWorld: pose([0.1, -0.2, 0.3], yawDegrees: 12))
        let pixel = SIMD2(100.0, 400.0)
        let point = view.center + view.ray(through: pixel) * 3.7
        let back = view.project(point)!
        XCTAssertEqual(back.x, pixel.x, accuracy: 1e-6)
        XCTAssertEqual(back.y, pixel.y, accuracy: 1e-6)
    }

    func testRecoversDistanceWithTwentyCentimeterSlide() throws {
        for distance in [4.0, 6.0, 8.0] {
            let reference = render(pose([0, 0, 0]), wall: distance)
            let moved = render(pose([0.2, 0.01, 0.02], yawDegrees: -1.5), wall: distance)
            let match = try Triangulation.distance(from: reference, to: moved, at: center).get()
            XCTAssertEqual(match.distance, distance, accuracy: distance * 0.03, "at \(distance) m")
            XCTAssertGreaterThan(match.score, 0.9)
        }
    }

    func testFlatWallHasNoTexture() {
        let reference = render(pose([0, 0, 0]), wall: 5, flat: true)
        let moved = render(pose([0.2, 0, 0]), wall: 5, flat: true)
        guard case .failure(let failure) = Triangulation.distance(from: reference, to: moved, at: center) else {
            return XCTFail("a flat wall should not match")
        }
        XCTAssertEqual(failure, .noTexture)
    }

    func testNarrowBaselineIsMuchLessPrecise() throws {
        // Same scene with the phone's own ~1 cm camera spacing: the sweep is far coarser at 6 m.
        let reference = render(pose([0, 0, 0]), wall: 6)
        let wide = try Triangulation.distance(from: reference, to: render(pose([0.2, 0, 0]), wall: 6), at: center).get()
        let narrow = Triangulation.distance(from: reference, to: render(pose([0.01, 0, 0]), wall: 6), at: center)
        // Either no reliable match, or a worse one.
        if case .success(let m) = narrow {
            XCTAssertGreaterThanOrEqual(abs(m.distance - 6), abs(wide.distance - 6))
        }
    }

    func testNCC() {
        let a: [Float] = [1, 2, 3, 4]
        XCTAssertEqual(Triangulation.ncc(a, a.map { $0 * 3 + 10 }), 1, accuracy: 1e-6)
        XCTAssertEqual(Triangulation.ncc(a, a.reversed()), -1, accuracy: 1e-6)
    }
}
