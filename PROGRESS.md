# Starfall — Development Progress

## Completed Steps

### Step 0 & Step 1 — Repo, CI Pipeline & App Skeleton (Sol Overview)
- Initialised Git repository, XcodeGen `project.yml`, `StarfallApp` Sol overview, and `.github/workflows/ci.yml` producing `Starfall_Unsigned.ipa`. Verified on iPad via Signulous.

### Step 2 — Scene, Debug Overlay & App Icon
- Added Concept 2 (Astrolabe Horizon) 1024×1024 app icon, non-AR `RealityView` with virtual perspective camera, procedural starfield skybox, and `DebugOverlayView` (locked 60.0 FPS, 141 MB RAM on iPad).

### Steps 3, 4, 5 & 6 (Milestone Build A) — Refined Starfield, Controller Input, 6DOF Flight, Floating Origin & 3D Sol Environment
- Verified on iPad: smooth 6DOF controller flight, radial-glow starfield, Floating Origin recentring, and 3D Sol environment with Gagarin Gateway ring station.

### Steps 7, 8 & 9 + Elite Dangerous Solo Career & Starport Services Upgrade (Gate G1 + Gate G2 Core Loop)
- **What was done:**
  - **True 3D-to-2D Perspective Target Projection & Modern Stick Aim (`SpaceSceneView.swift`, `ControllerInputManager.swift`, `FlightModel.swift`):**
    - Projects all 3D targets, lead reticles, and waypoints through `cameraEntity`'s exact vertical FOV matrix (`focalLengthPts = (H/2) / tan(FOV/2)`) so target boxes sit directly on top of 3D enemy ships/stations in both Cockpit and Chase views.
    - **Modern Twin-Stick Aiming (Default ON):** Left Stick steers nose (`Pitch` + `Yaw` with automatic banking into turns and horizon self-leveling); Right Stick controls `Throttle` (Up/Down) and `Roll` (Left/Right).
    - **Elite "Blue Zone" Sweet-Spot Agility (`40%–65%` Throttle):** Keeping your throttle in the cyan Blue Zone on the HUD gauge boosts pitch and yaw turn rates by `+35%` (`BLUE ZONE (MAX AGILITY)`).
    - **Target Auto-Track (`AUTO-AIM: ON`) & 20° Gimbal Convergence:** Smoothly tracks locked targets and converges both Pulse Lasers (`RT`) and Multi-Cannons (`LT`) inside the 20° forward gimbal ring.
  - **Frame Shift Drive — Supercruise & Witch-Space Hyperspace Jumps (`SpaceSceneView.swift`, `NavigationWaypointManager.swift`):**
    - Lock any local station, planet, moon, or combat zone and tap **`SUPERCRUISE`** for an FSD countdown and drop-out right at your destination.
    - Lock any neighboring star system (`Alpha Centauri`, `Barnard's Star`, `Sirius`, `Tau Ceti`, etc.) on the **Galaxy Star Chart (`[Y]`)** and tap **`HYPERSPACE JUMP`** to charge your FSD, blast through the **Witch-Space Hyperspace Conduit**, and arrive in that star system with its own planets, stations, and patrol zones loaded from `StarfallGalaxy`!
  - **Mail-Slot Docking & Starport Services (`CommanderProfile.swift`, `StarportServicesView.swift`):**
    - Fly into the glowing cyan mail-slot entrance of the orbital Ring Station (or tap **`DOCK PAD 04`** when within `1,500 m`) to dock inside the hangar and open **STARPORT SERVICES**:
      - **Station Contacts:** Refuel & repair hull, and redeem earned **Combat Bounty Vouchers** (`+12,500 CR` per pirate drone destroyed!).
      - **Commodities Market:** Buy low and sell high across 8 interstellar commodities with dynamic supply/demand pricing driven by each system's `Economy` (`High Tech`, `Industrial`, `Agriculture`, `Extraction`, `Refinery`, `Colony`).
      - **Mission Board:** Complete solo **Patrol Sweep** and **Security** contracts for `+25,000 CR` to `+65,000 CR` payouts.
      - **Outfitting Workshop:** Upgrade your **Frame Shift Drive** (`Class D → A`, up to `27.5 LY` jump range), **Bi-Weave Shield Generator**, **A-Rated Vector Thrusters**, and **Overcharged Gimbal Weapon Array**!
    - **Persistent Solo Save File:** Automatically saves your Commander profile (`Credits`, `Combat/Trade/Explorer Ranks`, `Cargo Hold`, `Outfitting Grades`, and `Current Star System`) to `Documents/starfall_commander_save.json` on your iPad.

### Milestone Build C — Living Frontier, EVE Tactical Overview, Asteroid Mining & 5-Hull Shipyard
- **What was done:**
  - **Collapsible EVE Tactical Overview + One-Tap Autopilot (`FlightHUDView.swift`, `SpaceSceneView.swift`, `CombatSystem.swift`):**
    - Collapsible right-hand **EVE Overview table** (`ALL`, `HOSTILES`, `MINING/LOOT`, `NAV/TRAFFIC`) sorted by live distance, with one-tap **`APPROACH`**, **`ORBIT 500M`**, **`TRACTOR`**, and **`WARP/DOCK`** commands (moving the flight stick automatically returns control to manual flight).
  - **Thermal Asteroid Mining & Magnetic Tractor Scoop (`CombatSystem.swift`, `CommanderProfile.swift`):**
    - Added procedural 3D **Asteroid Belt Alpha** (`Titanium`, `Core Crystal Ore`, `Void Opal Crystals`). Firing lasers/cannons at asteroids or pirates spawns physical 3D **Ore & Salvage Canisters** that automatically tractor-beam into your hold within `130m–260m` (or via the Overview `TRACTOR` button).
  - **5-Hull Shipyard with Custom 3D Ships & Cockpits (`CommanderProfile.swift`, `ShipEntityBuilder.swift`, `StarportServicesView.swift`):**
    - Added the **SHIPYARD** tab in Starport Services featuring `SF-1V Kestrel`, `SF-2A Viper`, `SF-4C Cobra Mk IV`, `SF-7T Atlas Barge`, and `SF-9X Astrolabe Corvette`.
  - **Living Universe, Dynamic Spectral 3D Stars, Planetary Rings & Procedural Signal Sources (`SolSceneBuilder.swift`, `NavigationWaypointManager.swift`):**
    - Hyperspace jumps dynamically re-color the 3D Star, Corona, Sunlight, Primary Planet, and **3D Planetary Rings** by spectral class and seed.
    - Added friendly **System Authority Enforcers**, **Trade Freighter Convoys**, **Mining Barges**, **Procedural Unidentified Signal Sources (`USS`)**, **Pirate Dread-Leader Bosses (`+25,000 CR`)**, **Enemy Return Fire**, **Live Radio Comms Chatter**, and **Procedural Cockpit Audio (`CockpitAudioManager.swift`)**.
