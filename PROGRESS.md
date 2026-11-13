# Starfall — Development Progress

## Completed Steps

### Step 0 & Step 1 — Repo, CI Pipeline & App Skeleton (Sol Overview)
- **What was done:**
  - Initialised Git repository and added `.gitignore` for Xcode, XcodeGen, SwiftPM, and unsigned IPA build outputs.
  - Created `project.yml` (XcodeGen specification) for the iPad-only `Starfall` app target (`iOS 17.0+`, `Swift 6.0`, landscape orientations, full screen, local package dependency on `StarfallGalaxy`, unsigned build flags).
  - Created `StarfallApp/StarfallApp.swift` and `StarfallApp/SolOverviewView.swift` importing `StarfallGalaxy` and displaying Sol's system summary, primary G2V star details, orbital/surface stations (Gagarin Gateway, Armstrong Landing, Tsiolkovsky Ring, etc.), and all 10 major planets/dwarf planets with their moons, orbits, surface gravity, temperature, habitable-zone badges, and landability status.
  - Added `.github/workflows/ci.yml` on `macos-15` (pinned to Xcode 16.2) that:
    1. Runs `swift test -v` in `StarfallGalaxy` (14 unit tests).
    2. Runs `xcodegen generate` and builds `Starfall` for `generic/platform=iOS` (`Release`, `CODE_SIGNING_ALLOWED=NO`).
    3. Packages `Payload/Starfall.app` into `Starfall_Unsigned.ipa` and uploads it as the `Starfall_Unsigned` build artifact.

- **How to verify:**
  1. Confirm the `Starfall CI` workflow run on GitHub Actions is green (`swift test` passes all 14 tests and the unsigned IPA step completes).
  2. Download the `Starfall_Unsigned` artifact from the GitHub Actions run summary and unzip it to get `Starfall_Unsigned.ipa`.
  3. Upload `Starfall_Unsigned.ipa` to Signulous, sign, and install on your iPad.
  4. Launch **Starfall** on your iPad in landscape orientation. You should see the dark-themed **STARFALL — SOL SYSTEM** overview listing:
     - System Overview (`Sol`, `#8000000000000000`, `G2V • Yellow star (G) • 5772 K`, population `22.0B`, High tech, High security).
     - 6 stations including Gagarin Gateway (Earth), Armstrong Landing (Moon), and Tsiolkovsky Ring (Mars).
     - All 10 Sol bodies (Mercury, Venus, Earth with Moon, Mars with Phobos/Deimos, Ceres, Jupiter, Saturn, Uranus, Neptune, Pluto) with habitable-zone and landability tags.

- **Known issues:**
  - None.

## Next Step

### Step 2 — Scene
- Replace the static overview entry screen with a full-screen non-AR `RealityView` using a virtual perspective camera and a procedural starfield skybox.
- Add the on-screen debug overlay displaying frame time (fps / ms), entity count, memory usage, and `ProcessInfo.thermalState`.
