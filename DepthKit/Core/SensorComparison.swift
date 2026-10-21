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
    /// Center distance over several shots, with a 95 % confidence interval.
    var lidarEstimate: Estimate? = nil
    var stereoEstimate: Estimate? = nil
    /// Mean gyroscope rotation rate while shooting (rad/s).
    var shake: Double? = nil
    /// Farthest distance in the stereo map (98th percentile).
    var stereoFarthest: Double? = nil

    /// Apple's two-camera depth is made for Portrait photos: relative, and it stops growing at a few meters
    /// (about 2.5 m on iPhone 15 Pro). A target beyond the farthest stereo value is out of its range.
    var isBeyondStereoRange: Bool {
        guard let l = lidarCenter, let s = stereoCenter, let far = stereoFarthest else { return false }
        return s < 0.8 * l && far < 0.85 * l
    }

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
        if isBeyondStereoRange, let l = lidarCenter, let far = stereoFarthest {
            return String(format: "Beyond the two-camera range. Apple's two-camera depth is built for Portrait photos and stops growing at about %.1f m here, so it can't reach a target at %.1f m. LiDAR still can (up to about 5 m).", far, l)
        }
        if let l = lidarEstimate, let s = stereoEstimate, l.margin != nil, s.margin != nil, l.overlaps(s) {
            return "Two cameras and LiDAR agree within their measurement uncertainty (\(max(percent, 1))% apart at the center)."
        }
        if percent <= 5 { return "Two cameras agree with LiDAR within \(max(percent, 1))% at the center." }
        if percent <= 15 { return "Two cameras are \(percent)% off LiDAR at the center: usable, not precise." }
        return "Two cameras are \(percent)% off LiDAR here: unreliable. Likely too far, too dark, or too little detail."
    }

    var darkNote: String? {
        isDark ? "The scene is dark. LiDAR still works because it sends its own infrared light; the cameras don't." : nil
    }

    static func compute(lidar: [Float], lidarSize: (width: Int, height: Int),
                        stereo: [Float]?, stereoSize: (width: Int, height: Int)?,
                        brightness: Double, lidarCenters: [Double] = [], stereoCenters: [Double] = [],
                        shake: Double? = nil) -> SensorComparison {
        // With several shots, the center distance is the robust mean of the per-shot centers.
        let lidarEstimate = RobustStats.estimate(lidarCenters)
        let stereoEstimate = RobustStats.estimate(stereoCenters)
        let lidarCenter = lidarEstimate?.value
            ?? PixelBuffers.centerMedian(depth: lidar, width: lidarSize.width, height: lidarSize.height, window: 9)
        guard let stereo, let stereoSize, stereo.count == stereoSize.width * stereoSize.height else {
            return SensorComparison(lidarCenter: lidarCenter, stereoCenter: nil, wholeImageError: nil,
                                    stereoCoverage: 0, brightness: brightness, lidarEstimate: lidarEstimate, shake: shake)
        }
        let stereoCenter = stereoEstimate?.value
            ?? PixelBuffers.centerMedian(depth: stereo, width: stereoSize.width, height: stereoSize.height, window: 9)

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
        var farSamples: [Double] = []
        farSamples.reserveCapacity(stereo.count / 16 + 1)
        for i in stride(from: 0, to: stereo.count, by: 16) where stereo[i].isFinite && stereo[i] > 0 {
            farSamples.append(Double(stereo[i]))
        }
        return SensorComparison(lidarCenter: lidarCenter, stereoCenter: stereoCenter,
                                wholeImageError: compared > 0 ? errorSum / Double(compared) : nil,
                                stereoCoverage: total > 0 ? Double(stereoValid) / Double(total) : 0,
                                brightness: brightness, lidarEstimate: lidarEstimate, stereoEstimate: stereoEstimate,
                                shake: shake, stereoFarthest: Geometry.percentile(farSamples, 0.98))
    }
}
