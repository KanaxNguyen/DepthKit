import Foundation

/// Developer options: algorithm parameters and debug tools, tunable on device.
/// Views bind with @AppStorage(DevSettings.Key…, store: AppGroup.defaults) using the matching `Default` value.
enum DevSettings {
    enum Key {
        static let enabled = "dev.enabled"
        static let showStats = "dev.showStats"
        static let showHeatmap = "dev.showHeatmap"
        static let readoutMinConfidence = "dev.readout.minConfidence"
        static let readoutWindow = "dev.readout.window"
        static let boxMinHeightCm = "dev.box.minHeightCm"
        static let boxMinConfidence = "dev.box.minConfidence"
        static let boxFrames = "dev.box.frames"
        static let boxHeightPercentile = "dev.box.heightPercentile"
        static let boxJumpCm = "dev.box.jumpCm"
        static let boxMinPoints = "dev.box.minPoints"
        static let trueDepthFiltering = "dev.trueDepth.filtering"
        static let levelTolerance = "dev.level.tolerance"
        static let compareShots = "dev.compare.shots"
        static let liveWindow = "dev.live.window"

        static let all = [enabled, showStats, showHeatmap, readoutMinConfidence, readoutWindow, boxMinHeightCm,
                          boxMinConfidence, boxFrames, boxHeightPercentile, boxJumpCm, boxMinPoints,
                          trueDepthFiltering, levelTolerance, compareShots, liveWindow]
    }

    enum Default {
        static let showStats = true
        static let showHeatmap = false
        static let readoutMinConfidence = 1
        static let readoutWindow = 5
        static let boxMinHeightCm = 2.0
        static let boxMinConfidence = 2
        static let boxFrames = 12
        static let boxHeightPercentile = 0.97
        static let boxJumpCm = 3.0
        static let boxMinPoints = 150
        static let trueDepthFiltering = true
        static let levelTolerance = 0.5
        static let compareShots = 5
        static let liveWindow = 20
    }

    private static var store: UserDefaults { AppGroup.defaults }

    static var isEnabled: Bool { store.bool(forKey: Key.enabled) }
    static var showStats: Bool { isEnabled && bool(Key.showStats, Default.showStats) }
    static var showHeatmap: Bool { isEnabled && bool(Key.showHeatmap, Default.showHeatmap) }

    static var readoutMinConfidence: UInt8 { UInt8(clamping: int(Key.readoutMinConfidence, Default.readoutMinConfidence)) }
    static var readoutWindow: Int { int(Key.readoutWindow, Default.readoutWindow) }
    static var boxFrames: Int { int(Key.boxFrames, Default.boxFrames) }
    static var trueDepthFiltering: Bool { bool(Key.trueDepthFiltering, Default.trueDepthFiltering) }
    static var levelTolerance: Double { double(Key.levelTolerance, Default.levelTolerance) }
    static var compareShots: Int { int(Key.compareShots, Default.compareShots) }
    /// Live readings kept for the ± interval (≈20 per second).
    static var liveWindow: Int { int(Key.liveWindow, Default.liveWindow) }

    static var boxOptions: BoxEstimator.Options {
        var options = BoxEstimator.Options()
        options.minHeight = Float(double(Key.boxMinHeightCm, Default.boxMinHeightCm) / 100)
        options.minConfidence = UInt8(clamping: int(Key.boxMinConfidence, Default.boxMinConfidence))
        options.heightPercentile = double(Key.boxHeightPercentile, Default.boxHeightPercentile)
        options.jumpBase = Float(double(Key.boxJumpCm, Default.boxJumpCm) / 100)
        options.minPoints = int(Key.boxMinPoints, Default.boxMinPoints)
        return options
    }

    static func resetToDefaults() {
        for key in Key.all where key != Key.enabled { store.removeObject(forKey: key) }
    }

    private static func int(_ key: String, _ fallback: Int) -> Int { store.object(forKey: key) as? Int ?? fallback }
    private static func double(_ key: String, _ fallback: Double) -> Double { store.object(forKey: key) as? Double ?? fallback }
    private static func bool(_ key: String, _ fallback: Bool) -> Bool { store.object(forKey: key) as? Bool ?? fallback }
}
