# Starfall — Development Progress

## Completed Steps

### Step 0 & Step 1 — Repo, CI Pipeline & App Skeleton (Sol Overview)
- Initialised Git repository, XcodeGen `project.yml`, `StarfallApp` Sol overview, and `.github/workflows/ci.yml` producing `Starfall_Unsigned.ipa`. Verified on iPad via Signulous.

### Step 2 — Scene, Debug Overlay & App Icon
- Added Concept 2 (Astrolabe Horizon) 1024×1024 app icon, non-AR `RealityView` with virtual perspective camera, procedural starfield skybox, and `DebugOverlayView` (locked 60.0 FPS, 141 MB RAM on iPad).

### Steps 3, 4, 5 & 6 (Milestone Build A) — Refined Starfield, Controller Input, 6DOF Flight, Floating Origin & 3D Sol Environment
- **What was done:**
  - **Starfield Visual Upgrade (`StarfieldGenerator.swift`):** Replaced solid diamond polygons with procedural radial-glow and 4-point diffraction-spike `TextureResource` sprites with UV mapping and alpha blending (`UnlitMaterial` `.transparent`), rendering pinpoint stars and glowing catalogue landmarks.
  - **Step 3 — Controller Input (`InputState.swift`, `ControllerInputManager.swift`):**
    - Connects to physical game controllers via `GCControllerDidConnect` / `GCControllerDidDisconnect` notifications and provides on-demand `GCVirtualController` touch fallback.
    - Implements the full Section 6 control mapping including the **Hold LB modifier layer**, dead-zone (`0.10`), and non-linear stick response curve (`exponent = 1.8`), plus live on-screen input logging.
  - **Step 4 — 6DOF Flight Model (`FlightModel.swift`, `ShipEntityBuilder.swift`, `FlightHUDView.swift`):**
    - Data-driven `ShipSpec` loaded from JSON for the **SF-1V Kestrel** Light Interceptor.
    - Fixed 60 Hz `FlightPhysics.stepFixedTick` with 6DOF rotational and linear thrusters, **Flight Assist ON** (damped velocity & angular rates) vs **Flight Assist OFF** (pure Newtonian uncoupled drift), boost impulse (`460 m/s`) with capacitor cooldown, and speed caps (`280 m/s`).
    - Built the 3D **SF-1V Kestrel** delta starfighter mesh with twin dynamic engine plumes and a first-person **Cockpit Canopy Frame** with G-force head motion, toggleable between **Cockpit** and **Chase** cameras (`RB` or HUD button).
    - Added the holographic `FlightHUDView` with boresight reticle, floating **Prograde Velocity Vector** drift pip, speed/throttle bar, boost capacitor status, and orbital navigation readout.
  - **Step 5 — Double-Precision Floating Origin (`FloatingOrigin.swift`, `GalacticPosition.swift`, `GalaxyTests.swift`):**
    - `WorldPositionComponent` and `FloatingOriginFrame` storing coordinates in `SIMD3<Double>` and recentring the local float origin whenever the player exceeds `2,000 m`.
    - Added `testFloatingOrigin1000KmFlightHasNoJitter` unit test in `StarfallGalaxyTests` verifying sub-millimetre precision across a 1,000+ km flight (15 total unit tests).
  - **Step 6 — Sol in 3D (`SolSceneBuilder.swift`):**
    - Loads `Sol` from `StarfallGalaxy` (`galaxy.system(galaxy.sol.id)`): places the **Sun** (with corona shells and directional sunlight), **Earth** (with procedural continents, clouds, polar caps, and cyan atmosphere rim glow), and **Moon** at true relative scale and direction using `PlanetaryBodyComponent` camera-relative projection.
    - Spawns the player in high Earth orbit `900 m` from **Gagarin Gateway**, a `320 m`-diameter rotating ring station with lit habitat windows, 4 spokes, a glowing cyan mail-slot docking entrance, navigation beacons, an approach buoy corridor, and wrapping space-dust speed particles.

- **How to verify on iPad:**
  1. Download `Starfall_Unsigned` from the latest green GitHub Actions run, sign with Signulous, and install on your iPad.
  2. Connect your game controller (or tap **Touch Pad** in the top-left telemetry box).
  3. **Visual check:**
     - Stars are now crisp, round glowing pinpricks with diffraction spikes on bright catalogue stars.
     - Directly ahead (`900 m`) is the rotating **Gagarin Gateway** ring station framed against **Earth** (with continents, clouds, and cyan atmosphere glow), the **Moon**, and the blazing **Sun**.
     - You are looking out through the **SF-1V Kestrel** cockpit canopy struts with the holographic HUD in the bottom corners (tap `▾ Hide` on the top-left telemetry box anytime to collapse it to a compact FPS pill).
  4. **Flight & Controller check:**
     - **Throttle (`Hold LB + RT / LT` or tap `50%` / `100%` on the HUD):** Accelerate toward Gagarin Gateway; watch space-dust particles streak past and the distance readout count down.
     - **Pitch / Roll (`Left Stick`) & Yaw / Vertical Thrust (`Right Stick`):** Bank and pitch around the rotating station ring, or fly right through the spokes.
     - **Lateral / Vertical Thrusters (`Hold LB + Left Stick`) & Cockpit Free-Look (`Hold LB + Right Stick` or finger drag):** Strafe around the station's docking slot and look around your cockpit.
     - **Camera Toggle (`RB` or tap `CAM: COCKPIT`):** Switch to **Chase Camera** to see your gunmetal-and-gold Kestrel starfighter banking in sunlight with twin cyan engine plumes that flare when you press **Boost (`A`)**.
     - **Flight Assist Toggle (`B` or tap `FA: ON`):** Boost up to speed, press `B` to turn **FA: OFF**, pitch 180° around, and watch the cyan **Prograde Vector Pip** and space dust show you drifting backward in pure Newtonian flight!
     - **Floating Origin:** Fly more than `2.0 km` away and watch `ORIGIN SHIFTS` increment on the bottom-left nav panel with zero jitter.

- **Known issues:**
  - None.

## Next Step

### Milestone Build B (Steps 7, 8 & 9) — Target Drones, Weapons, Power Distributor & Live Tuning Menu (Gate G1 Complete)
- **Step 7 — Targets and Weapons:** 3 AI target drones (orbit, strafe, evade), fixed pulse lasers (`RT`) + gimballed multi-cannons (`LT`), shields vs hull, hit feedback, `GCDeviceHaptics` controller rumble, and explosions.
- **Step 8 — Power Distributor:** `SYS / ENG / WEP` pips on the D-pad affecting shield regeneration, top speed / boost recharge, and weapon capacitor.
- **Step 9 — Feel Pass & Live Tuning Menu:** In-app debug tuning sliders on iPad so flight and weapon parameters can be adjusted live on device without rebuilding.
