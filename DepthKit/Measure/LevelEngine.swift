import CoreMotion
import Foundation
import Observation

/// A spirit-level reading, independent of Core Motion so it can be tested.
struct LevelReading: Equatable {
    enum Reference: Equatable {
        case edge(Double)
        case surface(roll: Double, pitch: Double)
    }

    /// Lying on a surface (screen up or down) rather than held on an edge.
    var isFlat = false
    /// Edge mode: rotation from upright in degrees, positive when turned clockwise.
    var edgeAngle: Double = 0
    /// Surface mode: positive when the right side is lower.
    var roll: Double = 0
    /// Surface mode: positive when the top edge is lower.
    var pitch: Double = 0
    var reference: Reference?

    /// Degrees off level on an edge: from the nearest right angle, or from the reference if one is set.
    var edgeDeviation: Double {
        if case .edge(let base)? = reference { return Self.wrap180(edgeAngle - base) }
        return Self.offRightAngle(edgeAngle)
    }

    var surfaceRoll: Double {
        if case .surface(let base, _)? = reference { return roll - base }
        return roll
    }

    var surfacePitch: Double {
        if case .surface(_, let base)? = reference { return pitch - base }
        return pitch
    }

    /// The angle that matters for this mode, always positive.
    var tilt: Double {
        isFlat ? max(abs(surfaceRoll), abs(surfacePitch)) : abs(edgeDeviation)
    }

    var slopePercent: Double { tan(tilt * .pi / 180) * 100 }

    func isLevel(tolerance: Double) -> Bool { tilt < tolerance }

    /// What to do to get level, as text and an SF Symbol.
    func hint(tolerance: Double) -> (text: String, systemImage: String) {
        if isLevel(tolerance: tolerance) { return ("Level", "checkmark.circle.fill") }
        if !isFlat {
            return edgeDeviation > 0
                ? ("Rotate counterclockwise", "arrow.counterclockwise")
                : ("Rotate clockwise", "arrow.clockwise")
        }
        if abs(surfaceRoll) >= abs(surfacePitch) {
            return surfaceRoll > 0 ? ("Raise the right side", "arrow.up.right") : ("Raise the left side", "arrow.up.left")
        }
        return surfacePitch > 0 ? ("Raise the top edge", "arrow.up") : ("Raise the bottom edge", "arrow.down")
    }

    static func offRightAngle(_ degrees: Double) -> Double {
        degrees - (degrees / 90).rounded() * 90
    }

    static func wrap180(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// Angles from a gravity vector in device coordinates (x right, y up, z out of the screen).
    /// `wasFlat` adds hysteresis so the mode doesn't flicker near 45°.
    static func angles(gx: Double, gy: Double, gz: Double, wasFlat: Bool) -> (isFlat: Bool, edge: Double, roll: Double, pitch: Double) {
        let degrees = 180 / Double.pi
        let flat = wasFlat ? abs(gz) > 0.7 : abs(gz) > 0.8
        let roll = asin(max(-1, min(1, gx))) * degrees
        let pitch = asin(max(-1, min(1, gy))) * degrees
        return (flat, atan2(gx, -gy) * degrees, roll, pitch)
    }
}

/// Streams gravity from Core Motion, smooths it, and publishes a `LevelReading`.
@Observable
final class LevelEngine {
    static let isSupported = CMMotionManager().isDeviceMotionAvailable

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var gravity: SIMD3<Double>?

    var isAvailable: Bool { manager.isDeviceMotionAvailable }
    private(set) var reading = LevelReading()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            let sample = SIMD3(g.x, g.y, g.z)
            let smoothed = gravity.map { $0 + (sample - $0) * 0.2 } ?? sample
            gravity = smoothed
            let a = LevelReading.angles(gx: smoothed.x, gy: smoothed.y, gz: smoothed.z, wasFlat: reading.isFlat)
            if a.isFlat != reading.isFlat { reading.reference = nil }
            reading.isFlat = a.isFlat
            reading.edgeAngle = a.edge
            reading.roll = a.roll
            reading.pitch = a.pitch
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }

    /// Measures relative to the current position, e.g. to match an existing slope.
    func setReference() {
        reading.reference = reading.isFlat
            ? .surface(roll: reading.roll, pitch: reading.pitch)
            : .edge(reading.edgeAngle)
    }

    func clearReference() { reading.reference = nil }
}
