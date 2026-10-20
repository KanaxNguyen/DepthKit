import CoreMotion
import Foundation
import Observation

/// Spirit level from gravity. Upright: tilt of the edge. Flat on a surface: tilt in two axes.
@Observable
final class LevelEngine {
    static let isSupported = CMMotionManager().isDeviceMotionAvailable

    @ObservationIgnored private let manager = CMMotionManager()

    var isAvailable: Bool { manager.isDeviceMotionAvailable }
    var isFlat = false
    /// Degrees. Upright: rotation from vertical. Flat: tilt left/right.
    var primary: Double = 0
    /// Degrees, flat only: tilt toward/away from you.
    var secondary: Double = 0

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            let reading = Self.reading(gx: g.x, gy: g.y, gz: g.z)
            self.isFlat = reading.isFlat
            self.primary = reading.primary
            self.secondary = reading.secondary
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }

    static func reading(gx: Double, gy: Double, gz: Double) -> (isFlat: Bool, primary: Double, secondary: Double) {
        let degrees = 180 / Double.pi
        if abs(gz) > 0.75 {
            return (true, asin(max(-1, min(1, gx))) * degrees, asin(max(-1, min(1, gy))) * degrees)
        }
        return (false, atan2(gx, -gy) * degrees, 0)
    }
}
