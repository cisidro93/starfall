# Starfall — Development Progress

## Completed Steps

### Step 0 & Step 1 — Repo, CI Pipeline & App Skeleton (Sol Overview)
- **What was done:**
  - Initialised Git repository and added `.gitignore` for Xcode, XcodeGen, SwiftPM, and unsigned IPA build outputs.
  - Created `project.yml` (XcodeGen specification) for the iPad-only `Starfall` app target (`Swift 6.0`, landscape orientations, full screen, local package dependency on `StarfallGalaxy`, unsigned build flags).
  - Created `StarfallApp/StarfallApp.swift` and `StarfallApp/SolOverviewView.swift` importing `StarfallGalaxy` and displaying Sol's system summary, primary G2V star details, orbital/surface stations, and all 10 major planets/dwarf planets with their moons.
  - Added `.github/workflows/ci.yml` on `macos-15` (pinned to Xcode 16.4) running `swift test -v` in `StarfallGalaxy` and packaging `Starfall_Unsigned.ipa`.
  - Verified on iPad via Signulous.

### Step 2 — Scene, Debug Overlay & App Icon
- **What was done:**
  - Added the 1024×1024 **Starfall** app icon (Concept 2: Astrolabe Horizon) in `StarfallApp/Assets.xcassets/AppIcon.appiconset` and configured `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` in `project.yml`.
  - Updated `project.yml` deployment target to iOS 18.0 for native `RealityView` (`content.camera = .virtual`) support.
  - Created `StarfallApp/Scene/StarfieldGenerator.swift` generating a procedural 3D starfield skybox around the origin, combining real catalogued stars from `StarfallGalaxy` (in their true galactic directions from Sol with spectral colours) with 2,600 deterministic background and Milky Way galactic-plane stars batched into 5 meshes for sub-millisecond GPU rendering.
  - Created `StarfallApp/Scene/SpaceSceneView.swift` with a full-screen non-AR `RealityView`, a virtual `PerspectiveCameraComponent` (`FOV = 60°`), smooth auto-pan + touch drag-to-look, a centre reticle, and a `SceneEvents.Update` frame loop.
  - Created `StarfallApp/UI/DebugOverlayView.swift` showing live **FPS**, **Frame Time (ms)**, **Entity Count**, **Memory (RSS + free headroom)**, and **Thermal State** (`ProcessInfo.processInfo.thermalState`), plus toggles for **Auto-Pan** and the **Sol Data** sheet.

- **How to verify:**
  1. Download the `Starfall_Unsigned` artifact from the latest green GitHub Actions run, sign via Signulous, and install on your iPad.
  2. Check your iPad home screen: the **Starfall** icon should now show the gold/gunmetal Astrolabe Horizon starfighter emblem.
  3. Launch **Starfall** in landscape:
     - You should see the full-screen 3D starfield skybox gently panning across the Milky Way band and spectral-coloured stars (with zero camera permission prompt).
     - Drag anywhere on the screen with one finger to look around the 3D starfield in any direction.
     - Check the top-left **STARFALL TELEMETRY** debug overlay: it should report a green status dot, `~60.0 FPS (16.67 ms)` (or `120.0 FPS` on ProMotion), `8` entities, memory usage + available headroom in GB, and `Thermal: Nominal`.
     - Tap **Auto-Pan: ON/OFF** to pause/resume camera rotation, and tap **Sol Data** to open the Sol system overview modal sheet.

- **Known issues:**
  - None.

## Next Step

### Step 3 — Controller Input
- Connect via `GCController` notifications (`GCControllerDidConnect` / `GCControllerDidDisconnect`) and log inputs.
- Build an `InputState` component updated each tick with the Section 6 mapping (`LB` modifier layer, pitch/roll/yaw/thrusters, throttle, boost, FA toggle, D-pad pips) plus dead-zone and response curve on the sticks.
- Add `GCVirtualController` touch fallback when no physical controller is connected.
