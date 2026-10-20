import Foundation

/// LiDAR versus Apple's two-camera (stereo) depth for one capture, in plain terms.
struct SensorComparison: Equatable {
    var lidarCenter: Double?
    var stereoCenter: Double?
    /// Mean |stereo − LiDAR| / LiDAR over pixels where both have depth.
    var wholeImageError: Double?
    /// Share of the image where stereo found depth.
    var stereoCoverage: Double
    /// Mean scene brightness, 0 (black) … 1 (white).
    var brightness: Double

    var isDark: Bool { brightness < 0.15 }

    /// Signed center difference as a fraction of the LiDAR distance.
    var centerDifference: Double? {
        guard let l = lidarCenter, let s = stereoCenter, l > 0 else { return nil }
        return (s - l) / l
    }

    var verdict: String {
        guard let difference = centerDifference else {
            return "The two cameras found no depth at the center. Stereo needs light and surface detail, and works best within about 2 m."
        }
        let percent = Int((abs(difference) * 100).rounded())
        if percent <= 5 { return "Two cameras agree with LiDAR within \(max(percent, 1))% at the center." }
        if percent <= 15 { return "Two cameras are \(percent)% off LiDAR at the center: usable, not precise." }
        return "Two cameras are \(percent)% off LiDAR here: unreliable. Likely too far, too dark, or too little detail."
    }

    var darkNote: String? {
        isDark ? "The scene is dark. LiDAR still works because it sends its own infrared light; the cameras don't." : nil
    }

    static func compute(lidar: [Float], lidarSize: (width: Int, height: Int),
                        stereo: [Float]?, stereoSize: (width: Int, height: Int)?,
                        brightness: Double) -> SensorComparison {
        let lidarCenter = PixelBuffers.centerMedian(depth: lidar, width: lidarSize.width, height: lidarSize.height, window: 9)
        guard let stereo, let stereoSize, stereo.count == stereoSize.width * stereoSize.height else {
            return SensorComparison(lidarCenter: lidarCenter, stereoCenter: nil, wholeImageError: nil,
                                    stereoCoverage: 0, brightness: brightness)
        }
        let stereoCenter = PixelBuffers.centerMedian(depth: stereo, width: stereoSize.width, height: stereoSize.height, window: 9)

        // Both maps cover the wide camera's view; compare on the LiDAR grid (nearest neighbour).
        var errorSum = 0.0, compared = 0, stereoValid = 0
        for y in 0..<lidarSize.height {
            let sy = min(stereoSize.height - 1, (y * stereoSize.height + stereoSize.height / 2) / lidarSize.height)
            for x in 0..<lidarSize.width {
                let sx = min(stereoSize.width - 1, (x * stereoSize.width + stereoSize.width / 2) / lidarSize.width)
                let s = stereo[sy * stereoSize.width + sx]
                guard s.isFinite, s > 0 else { continue }
                stereoValid += 1
                let l = lidar[y * lidarSize.width + x]
                guard l.isFinite, l > 0.1 else { continue }
                errorSum += Double(abs(s - l) / l)
                compared += 1
            }
        }
        let total = lidarSize.width * lidarSize.height
        return SensorComparison(lidarCenter: lidarCenter, stereoCenter: stereoCenter,
                                wholeImageError: compared > 0 ? errorSum / Double(compared) : nil,
                                stereoCoverage: total > 0 ? Double(stereoValid) / Double(total) : 0,
                                brightness: brightness)
    }
}
