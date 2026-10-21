import CoreMotion
import Foundation
import Observation

/// How much the iPhone is shaking, from the gyroscope. Used to wait for a steady hand before capturing
/// and to tell the user to hold still.
@Observable
final class MotionMonitor {
    /// Smoothed rotation rate in rad/s. A hand-held phone held still is typically below ~0.1.
    private(set) var shake: Double = 0

    var isSteady: Bool { shake < threshold }
    var threshold = 0.12

    @ObservationIgnored private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let r = motion?.rotationRate else { return }
            let magnitude = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
            shake += (magnitude - shake) * 0.25
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }

    /// Waits until the phone is steady, or until `timeout` passes. Returns the shake level at that moment.
    @MainActor
    func waitUntilSteady(timeout: Duration = .seconds(1.5)) async -> Double {
        guard manager.isDeviceMotionActive else { return 0 }
        let deadline = ContinuousClock.now + timeout
        while !isSteady, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return shake
    }

    static func describe(_ shake: Double) -> String {
        switch shake {
        case ..<0.06: "Very steady"
        case ..<0.12: "Steady"
        case ..<0.3: "Some shake"
        default: "Shaky"
        }
    }
}
