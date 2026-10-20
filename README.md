# DepthKit

A measuring app for iPhone that uses both depth sensors: the **LiDAR Scanner** on the back and the **TrueDepth camera** on the front. Its headline feature is **box dimensioning**: aim at a parcel and get length × width × height, volume and courier dimensional weight.

SwiftUI, iOS 18+, no network, no account. Camera frames are processed on device and never stored.

## Features

| Mode | Sensor | What it does |
|---|---|---|
| **Distance** | LiDAR | Point-to-point distance between two surfaces |
| **Range** | LiDAR | Distance from the iPhone to whatever is under the crosshair, with a confidence badge |
| **Box** | LiDAR | Length × width × height of a box on the floor, plus volume and dimensional weight (÷5000 or ÷6000) |
| **Near** | TrueDepth | Close-range distance (about 20 cm – 1 m) from the front camera |
| **Level** | Motion | Spirit level, upright or flat on a surface |

The app also includes:

- **History.** Every saved result, with swipe to delete and CSV export.
- **Siri and Shortcuts** (App Intents), with no setup needed:
  - "Measure a box with DepthKit"
  - "Measure distance with DepthKit"
  - "Open the level in DepthKit"
  - "What was my last measurement in DepthKit". Siri answers this one without opening the app.
- **Widgets.** Home Screen widgets in small and medium sizes; the medium one has Box and Distance shortcuts. There are also Lock Screen widgets in rectangular and inline styles.
- **Control Center.** The Measure Box and Measure Distance controls open the app straight into that mode.
- **Design.** Follows the Human Interface Guidelines: system components, SF Symbols, Dynamic Type, VoiceOver labels, haptics, and Liquid Glass on iOS 26 and later.

## How box measuring works

`DepthKit/Core/BoxEstimator.swift` is pure Swift and unit-tested without a device.

1. ARKit detects the floor plane and supplies a smoothed LiDAR depth map (256 × 192) with per-pixel confidence.
2. Each high-confidence pixel is unprojected to a world point using the camera intrinsics, scaled to depth resolution, and the camera pose.
3. Starting from the crosshair, a flood fill collects pixels that sit at least 2 cm above the floor and have continuous depth. This set of pixels is the box.
4. **Height** is the 97th percentile of the region's height above the floor.
5. **Footprint.** The region is projected onto the floor. The app takes its convex hull, then the minimum-area enclosing rectangle by rotating calipers, which gives length and width at any yaw.
6. Twelve frames are measured, and the median of each dimension is reported. The 3D wireframe is drawn back over the camera view.

## Project layout

```
DepthKit/
  App/        app entry, router (deep links depthkit://measure/<mode>), App Shortcuts
  Measure/    AR (LiDAR), TrueDepth and motion engines; measuring UI
  Core/       geometry, box estimator, pixel buffer helpers (no ARKit dependency)
  History/    history list, CSV export
  Settings/   units, dimensional-weight divisor, Siri tip
DepthKitWidgets/  widgets and Control Center controls
Shared/       models, App Group store, App Intents (compiled into app and widgets)
DepthKitTests/    geometry, box estimator (synthetic depth maps), store, formatting, router
```

## Build

```bash
brew install xcodegen      # once
xcodegen generate
open DepthKit.xcodeproj
```

Set your team in `project.yml` (`DEVELOPMENT_TEAM`) or in Xcode's Signing & Capabilities. The app and its widget share the App Group `group.vn.kanax.depthkit`; change it in both entitlements and `Shared/SharedStore.swift` if you use a different bundle ID.

```bash
xcodebuild -project DepthKit.xcodeproj -scheme DepthKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

The Simulator has no LiDAR, TrueDepth or motion sensors. Each mode shows what the device lacks instead of failing. To measure for real, use an iPhone Pro: LiDAR is needed for Distance, Range and Box.

## Limitations

- Box mode expects a roughly rectangular box resting on the floor or a table that ARKit has detected as a plane.
- Dark, shiny or transparent surfaces give LiDAR less valid depth. Results are estimates, typically within 1–2 cm at arm's length; check anything critical with a tape measure.

## Roadmap

- Fine-tune a monocular depth model (Depth Anything V2 Small) on paired RGB + LiDAR captures and run it with Core ML, so iPhones without LiDAR can estimate distances, and compare it with LiDAR live.
- Live Activity for multi-box measuring sessions.
