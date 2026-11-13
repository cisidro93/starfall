# Starfall — Project Brief for the AI Coding Agent

Read this whole file before doing anything. It is the source of truth for what Starfall is,
what has been built, how the code is organised, and what to build next.

---

## 1. Your role and how to work with me

You are a senior game developer specialising in Swift, Apple platforms and real-time 3D
(RealityKit, Metal, GameController). You are building **Starfall**, a native, offline,
single-player space simulation for iPad, in the spirit of Elite Dangerous.

About me (Chris): I build working software through AI-assisted coding. I don't have a
formal programming background, so:

- **Explain before you change.** Before a multi-file change, give me a short plan: which
  files, what changes, why. Wait for my OK on anything large or hard to undo.
- **Small, testable steps.** One feature at a time. After each step, tell me exactly how to
  verify it (which scheme to run in Xcode, what I should see, which test to run).
- **Keep the build green.** Never leave the project in a state that doesn't compile. Run
  `swift build` and `swift test` (or the Xcode equivalent) after changes and tell me the result.
- **Plain language.** When something goes wrong, tell me what broke, why, and what you'll do
  about it. No jargon without a one-line explanation.
- **Don't invent facts.** If you don't know an Apple API detail, say so and check the
  documentation rather than guessing.
- **Ask, don't assume**, when a decision changes gameplay, art direction or save data.

### My development environment (important)

- I work on **Windows** in Antigravity. Project folder:
  `C:\Users\chris\.gemini\antigravity\scratch\starfall`
- **There is no Mac and no local Xcode.** I cannot open an `.xcodeproj`, run the iOS Simulator
  or use Instruments. Do not give me instructions that need them.
- **iOS builds happen in GitHub Actions** on a macOS runner, which produces an **unsigned IPA**
  that I sideload onto my iPad with **Signulous**. This is the same pipeline I use for my other
  iOS app. Every app change is verified by: push → CI build green → download the IPA artifact →
  sideload → test on the iPad with a controller.
- **Generate the Xcode project; don't hand-maintain it.** Use **XcodeGen** (`project.yml`
  committed to the repo; CI runs `xcodegen generate` before `xcodebuild`). Never hand-edit
  `.pbxproj` files.
- **The `StarfallGalaxy` package can be tested without a Mac.** CI runs `swift test` on macOS.
  Locally I can optionally install the Swift toolchain for Windows and run `swift build` /
  `swift test` in the package folder. RealityKit, GameController and other Apple frameworks
  exist only in the app target, never in the package.
- **Watch for Swift 6 compiler problems on CI.** In my other app, complex SwiftUI `body`
  closures caused type-checker crashes (fixed by moving complex expressions such as
  `.first(where:)` into computed properties), and MainActor isolation needed explicit fixes.
  Keep SwiftUI views small and expressions simple from the start.
- **Performance is measured on device**, with an in-app debug overlay (frame time, entity
  count, memory, thermal state from `ProcessInfo.thermalState`) and logs, since Instruments isn't
  available.

### Checkpoint protocol (follow every time)

For each numbered step in section 8:

1. **Plan:** list the files you'll create or change and why. Wait for my OK.
2. **Build:** make the change in small commits with clear messages.
3. **Verify:** `swift test` for the package; for app changes, push and confirm the CI build is
   green. Paste me the result. If CI fails, read the log, explain the cause, fix it.
4. **Device check:** tell me exactly what to do on the iPad and what I should see.
5. **Record:** update `PROGRESS.md` (done / how to verify / known issues / next).
6. **Stop** and wait for my confirmation before starting the next step.

---

## 2. The game in one paragraph

Starfall is an original, single-player space sim for iPad played with a game controller. You
start at Earth with a small ship and a little money, in a 1:1-scale Milky Way of about 113
billion star systems. You fly with six-degrees-of-freedom Newtonian physics, dock at
stations, trade, fight pirates, take missions, explore and scan, upgrade your ship and work
your way out from the safe, crowded core of human space into a lawless frontier and the
unexplored galaxy beyond. Long-term, it aims for feature parity with Elite Dangerous as it
stands in late 2026, delivered across four major releases. It runs fully offline at a locked
60 fps.

### Pillars

1. **Flight feels physical.** 6DOF Newtonian flight, flight assist on/off, lateral and vertical
   thrusters, boost, and a power distributor (SYS / ENG / WEP pips).
2. **A galaxy you can't finish.** A 1:1 Milky Way, procedural beyond Sol's real neighbourhood.
3. **Many ways to earn.** Trading, bounty hunting, missions, exploration, later mining and more,
   all feeding one loop: better ship, better outfitting, further out.
4. **Console-quality on iPad.** 60 fps, full controller play, instant suspend/resume, no network.

### Hard rules

- **Original IP only.** Borrow the genre and mechanics, never the brand. No Elite Dangerous or
  Frontier names, ship names, factions, alien species, UI art, logos, audio or data files. Use
  our own names for everything (including the in-system travel mode and hyperspace drive).
- **Single-player, offline.** No servers, no accounts. Multiplayer features get single-player
  equivalents (AI wingmates, AI crew, offline "community" events).
- **No paid shortcuts.** One-time purchase per release. No premium currency, no pay-to-skip.
- **Swift-native.** No Unity, Unreal or Godot unless I explicitly decide to switch.

---

## 3. Design principles from player research

We researched what the Elite Dangerous community loves and dislikes today. Treat these as
design requirements, not suggestions.

**Keep (what players love):**
- Weighty, satisfying flight model — tune it until it feels right before building on it.
- Sense of scale, atmosphere, and great ship and engine sound.
- Sandbox freedom: every career viable from the starter ship.
- Play at your own pace: pause anywhere, instant suspend/resume.
- Fast in-system travel, deterministic (non-random) ship upgrades, sane material gathering —
  build these in from day one.

**Fix (what players dislike):**
- **Grind.** Materials drop from normal play in useful amounts; an in-game "shopping list" for
  any upgrade blueprint; every upgrade reversible; no farming exploits needed. Target 40–60
  hours from starter ship to endgame ship. Earnings scale with risk, not repetition.
- **"Mile wide, inch deep."** Chained mission arcs, a light main story, and faction states that
  visibly change because of what the player did.
- **Steep onboarding.** A short tutorial campaign, contextual controller prompts, one-button
  route plotting, plain-language UI.
- **Samey locations.** Hand-authored set pieces seeded among procedural content.
- **Buggy, slow launches.** Each release ships only when it meets the performance budget and
  passes TestFlight playtesting.
- **Tedious solo colonisation (4.0).** Any activity contributes; quantities sized for one
  player; hire NPC freighters.

---

## 4. Scope and releases

Each release is a complete, shippable game. Everything in 1.0 must be designed so 2.0–4.0
extend it rather than rewrite it (ship, inventory, materials and faction data models must
already allow for landings, on-foot play and colonisation).

| Release | Timeframe (estimate) | Contents |
| --- | --- | --- |
| **1.0 Launch** | ~16 months | 6DOF flight, in-system cruise + hyperspace jumps, docking (manual + auto), stations, outfitting, ~10 ships, combat (lasers, multi-cannons, missiles, shields, subsystem targeting, NPC AI), trading with supply/demand, bounty hunting, mission board, reputation, exploration scanning, galaxy map, tutorial, background galaxy sim |
| **2.0 Surface** | Year 2 | Airless planetary landings, 6-wheel rover, mining (laser, core, subsurface), engineers + blueprints + materials, AI crew + ship-launched fighters, AI wingmates, more ships |
| **3.0 Frontier** | Year 3 | On-foot play in stations and surface outposts, suits and handheld weapons, personal carrier (mobile base), exobiology, thin-atmosphere landings, original alien threat + salvaged alien tech |
| **4.0 Dominion** | Year 4 | Powerplay-style rival powers with a shifting control map, system colonisation (build stations/outposts), capital-ship boarding, 30+ ships — feature parity reached |

### Milestones and gates (no phase starts until its gate passes)

| Phase | Months | Deliverables |
| --- | --- | --- |
| Prototype | 1–3 | Grey-box ship with 6DOF + flight assist, controller input, floating origin, one station, target drones |
| Vertical slice | 4–8 | One system: dock, trade, fight; outfitting; 3 ships; save/load; first TestFlight |
| Content to 1.0 | 9–16 | Galaxy integration, 10 ships, missions, factions, tutorial, polish, App Store launch |

- **G1 — Flight is fun:** five minutes of dogfighting drones is enjoyable on a controller at a locked 60 fps.
- **G2 — Full loop playable:** dock, buy cargo, jump, sell, fight, repair, upgrade and save, with no debug tools.
- **G3 — 1.0 shipped:** 10 testers finish the tutorial unaided; 40-hour career path works; App Store approved.
- **G4 — 2.0 shipped:** landings hold the frame budget; every engineering material drops from normal play.
- **G5 — 3.0 shipped:** on-foot and flight share one save, one controller scheme and the same performance budget.

---

## 5. Tech stack

| Layer | Choice |
| --- | --- |
| Language | Swift 6, strict concurrency |
| Rendering & scene | RealityKit (non-AR `RealityView` with a virtual camera) and its ECS |
| Custom visuals | Metal shaders (`CustomMaterial` / ShaderGraph): star coronas, procedural planets, hyperspace effect, engine trails |
| Input | GameController framework (`GCController`); `GCVirtualController` as touch fallback; `GCDeviceHaptics` for rumble |
| Menus / station UI | SwiftUI overlays |
| Audio | RealityKit spatial audio + AVAudioEngine for music |
| Saves | Versioned Codable snapshots on disk, optional iCloud (CloudKit) sync |
| Assets | Blender → USDZ (Reality Composer Pro is Mac-only, so build scenes in code; USDZ files load directly) |
| Project / build | XcodeGen `project.yml` + GitHub Actions macOS runner → unsigned IPA → Signulous sideload |
| Do not use | SceneKit (deprecated) |

**Target hardware:** M1-or-newer iPads (iPad Pro, iPad Air) as baseline; A17 Pro iPad mini as
the floor. Locked 60 fps, optional 120 fps on ProMotion.

### Performance budget (60 fps = 16.6 ms per frame)

| Area | Budget |
| --- | --- |
| Rendering (GPU) | ≤ 10 ms |
| Physics + AI | ≤ 3 ms |
| Gameplay + UI | ≤ 2 ms |
| Memory | ≤ 3 GB on 8 GB iPads |
| Install size | ≤ 4 GB at 1.0, on-demand resources for later content |

Test 60-minute sessions on the oldest supported iPad; iPads throttle when hot. (Profiling is
done on device with the in-app debug overlay; see section 1.)

### Art direction

"Stylized realism." Match Elite's *feel* where it's cheap and high-impact: dominant stars with
bloom and glare, hard light and truly black shadows, procedural planets with atmosphere rim
glow and rings, particles (engine trails, shield ripples, explosions, space dust for speed),
and a detailed cockpit. Go simpler where it's expensive: ships at 5–8k triangles with strong
silhouettes, stylized planet surfaces, kit-built station interiors, clean (not photoreal)
characters. Players forgive simpler models; they don't forgive stutter.

---

## 6. Architecture

One Swift package per module on a shared core. Later releases add new modules, not rewrites.

```
App shell (SwiftUI: menus, station services, galaxy map, settings, save slots)
   ↓
1.0 gameplay modules: Flight · Combat · Ships · Economy · Galaxy
   ↓
2.0–4.0 expansion modules (later): Surface · Crew · On-foot · Dominion
   ↓
Core: ECS world (RealityKit entities, floating origin) · Sim clock (60 Hz fixed tick,
      background galaxy sim) · Game data (JSON ships/modules/commodities/blueprints) · Saves
   ↓
Platform: RealityKit + Metal, GameController, spatial audio, CloudKit
```

Rules:
- **Modules talk only through ECS components and a typed event bus** (`ShipDestroyed`,
  `CargoSold`, `JumpCompleted`, …), never by calling each other directly.
- **Data-driven.** Ships, modules, commodities, engineers and blueprints live in JSON so balance
  changes need no code.
- **Fixed 60 Hz simulation tick**, separate from rendering.
- **Floating origin from day one.** The world recentres on the player; positions are stored as
  `SIMD3<Double>`; rendering uses camera-relative transforms. Beyond ~10 km from origin, Float
  jitter appears otherwise.
- **Versioned saves with migrations** from the very first save format.
- **Small files, unit tests per system.** Review every generated file; keep code maintainable.

### Core systems (build in this order — each feeds the next)

1. **Flight model** — 6DOF physics, flight assist damping, per-ship speed caps, boost, power distributor.
2. **Space scale** — floating origin, double-precision positions, layered rendering (stars / planets / near objects).
3. **Travel** — normal flight, in-system cruise at light-speed multiples, hyperspace jumps with fuel and mass-based jump range.
4. **Ships & outfitting** — hulls with hardpoints and internal slots; modules with mass, power draw, class and rating; loadout validator.
5. **Combat** — gimballed/fixed weapons, heat, shields vs hull, subsystem targeting, behaviour-tree NPC AI with skill tiers.
6. **Galaxy** — ✅ generator built (see section 7).
7. **Stations & docking** — docking request, pad assignment, entry slot, auto-dock; market, outfitting, shipyard, missions, repair.
8. **Economy & missions** — prices from economy type + drifting supply/demand; courier, delivery, kill and scan missions; reputation.
9. **Exploration & factions** — discovery scanner, detailed body scans, selling data; faction reputation, bounties, police response.

### Controls (controller-first, LB as modifier layer)

| Input | Default | Hold LB |
| --- | --- | --- |
| Left stick | Pitch / roll | Lateral + vertical thrust |
| Right stick | Yaw / vertical thrust | Look around cockpit |
| RT / LT | Primary / secondary fire | Throttle up / down |
| A | Boost | Deploy/retract hardpoints |
| B | Flight assist toggle | Landing gear |
| X | Target ahead | Next subsystem |
| Y | Galaxy/system map | Cargo scoop |
| D-pad | Power pips (SYS/ENG/WEP, reset) | Cockpit panel navigation |
| Menu / View | Pause / cockpit panels | — |

Full remapping stored per controller, using `GCController` element names so on-screen glyphs
match the actual pad. Design for the 11-inch iPad first; text ≥ 14 pt.

---

## 7. What already exists: the `StarfallGalaxy` package

The galaxy generator is built and tested and lives in the `StarfallGalaxy` folder. It is a
pure-Swift package (Swift 6 tools, iOS 17+ / macOS 14+, no dependencies, no graphics code).
Read its `README.md` and source before changing anything.

### What it does

A deterministic function from one 64-bit seed to the entire Milky Way. Nothing is stored:
space is cut into 10 ly cells, and each cell's stars come from `hash(seed, cell)`, so any
region generates instantly and identically every time.

- **Real sky near home:** Sol (hand-built from real data: all planets, major moons, Ceres,
  Pluto), every star within ~13.5 ly, famous stars out to Deneb, Sagittarius A*, and confirmed
  exoplanets (Proxima Centauri b/d, Teegarden b/c, Barnard's b, and others) at measured orbits.
  Inside 13.5 ly every star is real; no procedural stars are generated there.
- **Real galaxy shape:** tilted central bar, bulge and nucleus, 2 major + 2 minor logarithmic
  spiral arms at 13° pitch, a local spur through Sol, thin + thick disks, halo, patchy arms and
  dust lanes. Calibrated to the real density at Sol (0.0033 systems/ly³).
- **Stars:** O–M, brown dwarfs (L/T/Y), white dwarfs, neutron stars, black holes, giants and
  supergiants, with physically consistent mass, radius, temperature and luminosity. Hot stars
  cluster on arms; old stars in the bar/bulge. Remnants are kept rare so they're worth finding.
- **Bodies:** planets, belts, moons, rings; orbit, temperature, gravity, atmosphere,
  habitable zone, and landability (`airless` = 2.0, `thinAtmosphere` = 3.0).
- **Human space radiates from Earth:** Sol is the capital (22 billion people, stations Gagarin
  Gateway, Armstrong Landing, Tsiolkovsky Ring). Real stars within 30 ly are always populated;
  settlement falls off with distance (reach 140 ly), becomes a lawless frontier past ~200 ly,
  and stops at 450 ly. Each populated system has population, economy, security and named stations.
- **Names:** 2,000 ly naming regions with pronounceable names; systems get unique designations
  such as "Zybelval DX-20100 1". Sol sits in the middle of its region.
- **Routes:** weighted A* route planner with jump range.
- **Galaxy map image:** `GalaxyMapRenderer` renders the top-down Milky Way image.

### Files

| File | Purpose |
| --- | --- |
| `GalacticPosition.swift` | Light-year positions, Sol at origin; RA/Dec/distance → game frame; `CellCoordinate` (10 ly cells) |
| `SeededRandom.swift` | `SplitMix64` RNG, hashing, deterministic value noise |
| `DensityModel.swift` | Milky Way density model |
| `Catalogue.swift` | Real star systems and known exoplanets |
| `Stars.swift` | Stellar classes, `Star`, class weighting by environment |
| `Bodies.swift` | Planets, moons, belts; hand-built Sol system |
| `Settlement.swift` | Population, economy, security, stations |
| `Naming.swift` | Region names and system designations |
| `Galaxy.swift` | Public API, `SystemID`, `SystemSummary`, `StarSystem`, route planner, `MinHeap` |
| `GalaxyMap.swift` | Galaxy map renderer (PPM/RGB output) |
| `Sources/galaxy-cli/main.swift` | Command-line explorer (`stats`, `near`, `system`, `route`, `map`, `export`) |
| `Tests/StarfallGalaxyTests/GalaxyTests.swift` | 14 tests |

### Public API

```swift
import StarfallGalaxy

let galaxy = Galaxy()                                        // default seed 0x57A2FA11D21F7001
let nearby = galaxy.systems(within: 20, of: .sol)            // [SystemSummary], nearest first
let sol = galaxy.system(galaxy.sol.id)                       // StarSystem: stars, bodies, settlement
let tauCeti = galaxy.system(named: "Tau Ceti")               // catalogued systems by name
let path = galaxy.route(from: galaxy.sol.id, to: tauCeti!.id, jumpRange: 7.5)
let all = galaxy.catalogue                                   // every real system
let image = GalaxyMapRenderer.render(galaxy, size: 1024)     // galaxy map
let saved = tauCeti!.id.description                          // "#8000..." — store this in saves
let restored = SystemID(string: saved)
```

### Conventions you must preserve

- **Coordinate frame:** light-years, Sol at (0, 0, 0). **+z toward the galactic centre**,
  **+x along galactic longitude 90°** (direction of rotation), **+y toward the north galactic pole**.
  Sagittarius A* is at about (−26, −21, 26,670).
- **Determinism is sacred.** Same seed → same galaxy, forever. All randomness goes through
  `SplitMix64` and its own helpers (never Swift's `random(in:)`, whose algorithm can change
  between Swift versions). Star counts use only basic arithmetic, and density is quantised
  before counts are drawn.
- **Summary and detail must agree.** `SystemSummary` and `StarSystem` draw the same opening
  values from the same per-system RNG stream. If you add a new random draw, add it **after**
  the existing draws, or every existing system changes.
- **`SystemID` layout is permanent.** Catalogue IDs: top bit set + catalogue index. Procedural
  IDs: 16 bits each for cell x/y/z (offset by 32,768) + 15 bits for index within the cell.
  Saves store IDs, never array positions.
- **Catalogue order is permanent.** Catalogue IDs are indices, so **append** new real stars to
  the end of `StarCatalogue.entries`; never insert or reorder.
- **Changing anything that alters generated output** (seed, density, class weights, draw
  order, naming) is a breaking change: tell me first. Once saves exist it needs a migration.
- `Galaxy` is a `Sendable` value type with no internal cache. Generate off the main thread;
  the app keeps its own cache of recently opened systems.

### Measured output (default seed)

- ~113 billion systems in the galaxy; 109 within 20 ly (astronomers count ~110); 1,716 within
  50 ly; 13,950 within 100 ly; 25,306 populated systems within 250 ly.
- Full system detail generates in under 1 ms.
- Sol → Betelgeuse (548 ly) at 40 ly jump range: 15 jumps, ~3 s to plot.

### Known gaps

1. **Not yet built for iOS.** It was built and tested with Swift 6 on Linux. It only uses
   Swift + Foundation, so it should build cleanly for iPad, but the first green CI build of
   the package on macOS is the real confirmation. Fix any platform issues before anything else.
2. **Real star data is approximate**, hand-entered from published values. Before release,
   replace or extend with a proper catalogue import (e.g. the HYG database from Hipparcos/Gaia,
   CC BY-SA — needs attribution in credits), appended without breaking existing IDs.
3. **Long routes are slow.** Add a neighbour cache and run the planner on a background task
   with progress UI before 1.0.
4. **Cross-platform float differences.** Planet details use `pow`/`log`, which may differ in
   the last digit between platforms. Fine for gameplay; only matters if comparing iPad
   output against Linux test output.
5. **Galaxy map render is slow** (~50 s at 1024²). Pre-render it once and ship it as an asset,
   or move it to a Metal compute shader later.

---

## 8. Next task: the G1 flight prototype

Goal: pass gate **G1 — five minutes of dogfighting drones is fun on a controller at a locked
60 fps.** Work through these in order, one step at a time, verifying each before moving on.

0. **Repo and CI first.** Initialise git with a `.gitignore` for Xcode/Swift (ignore `.build/`,
   `*.xcodeproj`, `DerivedData/`). Ask me for the GitHub repo name before creating or pushing
   anything. Add a GitHub Actions workflow on a macOS runner that (a) runs `swift test` in
   `StarfallGalaxy`, (b) installs XcodeGen, generates the project, builds the app for iOS with
   code signing disabled, and (c) packages an unsigned `Starfall_Unsigned.ipa` as a downloadable
   build artifact. Pin the Xcode version explicitly in the workflow. Get this green before step 1.
1. **App skeleton.** Folder layout:
   ```
   starfall/
     project.yml              # XcodeGen spec: iPad-only app target, Swift 6, iOS 17+
     StarfallApp/             # app sources (SwiftUI entry point, RealityKit scene, systems)
     StarfallGalaxy/          # existing package, added as a local package dependency
     .github/workflows/       # CI
     STARFALL_BRIEF.md  PROGRESS.md
   ```
   A minimal SwiftUI app that imports `StarfallGalaxy` and shows Sol's name and planet list.
   Exit: CI green, IPA sideloads and launches on my iPad.
2. **Scene.** A full-screen non-AR `RealityView` with a virtual perspective camera and a
   procedural starfield skybox. Add the debug overlay (frame time, thermal state, memory).
3. **Controller input.** Connect via `GCController` notifications; log every input; build an
   `InputState` component fed from the controller each tick, with the mapping in section 6
   and a dead-zone + response curve on the sticks. `GCVirtualController` touch fallback.
4. **Flight model.** A grey-box ship entity with a `FlightComponent` and `FlightSystem` on a
   fixed 60 Hz tick: 6DOF thrust, per-axis max rates, flight assist on (damps to commanded
   velocity) and off (pure Newtonian), boost with cooldown, speed caps. All tuning values in
   a JSON ship spec. Cockpit and chase cameras.
5. **Floating origin.** World positions in `SIMD3<Double>`; recentre when the player is more
   than a few km from origin; render camera-relative. Add a test that flies 1,000 km and checks
   for no jitter.
6. **Sol.** Load Sol from `galaxy.system(galaxy.sol.id)`: place the Sun, Earth and Moon at
   correct relative scale and direction (orbits can be static for now), with a simple lit
   sphere for each. Spawn the player near Earth beside a placeholder ring station.
7. **Targets and weapons.** Target drones with simple AI (orbit, strafe, evade); a fixed laser
   and a gimballed multi-cannon; shields and hull; hit feedback, controller haptics, explosions.
8. **Power distributor.** SYS / ENG / WEP pips on the D-pad affecting shield regen, speed and
   weapon capacitor.
9. **Feel pass.** Tune with me in short sessions. Expose key flight values in a debug menu on
   the iPad so I can tune without a rebuild. Check the frame budget with the debug overlay.

Exit criteria: debug overlay shows a steady 60 fps on my iPad for a 10-minute session; I can dogfight three
drones with a controller and it feels good; flight assist on/off both work; all tests pass.

---

## 9. Reference documents

- Production plan (full plan, research, roadmap): https://claude.ai/artifact/TTxigETtR768SJ54Annt6U
- Galaxy showcase (rendered galaxy + explorable star chart): https://claude.ai/artifact/JUcru4N6gVwdUuJJ1gke46

When you finish a step, update a `PROGRESS.md` in the project root with what was done, how to
verify it, and what's next, so the next session can pick up where this one left off.
