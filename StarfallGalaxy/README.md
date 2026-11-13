# StarfallGalaxy

The galaxy generator for Starfall: a 1:1 Milky Way of about 113 billion star systems,
starting from Earth. Sol and its real neighbours come from astronomical data; everything
else is generated on demand from one 64-bit seed, identically every time.

Pure Swift, no dependencies, no graphics code. Swift 6, iOS 17+ / macOS 14+.

## What's in it

| File | What it does |
| --- | --- |
| `GalacticPosition.swift` | Positions in light-years, Sol at the origin, +z toward the galactic centre. Converts real star coordinates (RA/Dec/distance) into game space. |
| `SeededRandom.swift` | SplitMix64 generator, hashing and value noise. Everything is derived from these, so the galaxy is reproducible. |
| `DensityModel.swift` | The Milky Way's shape: bar, bulge, 2 major + 2 minor spiral arms, local spur, thin/thick disk, halo, dust. Calibrated to the real star density at Sol. |
| `Catalogue.swift` | Real systems: Sol, every star within ~13 ly, famous stars out to Deneb, Sagittarius A*, and confirmed exoplanets (Proxima b, Teegarden b/c, and others). |
| `Stars.swift` | Stellar classes O–M, brown dwarfs, white dwarfs, neutron stars, black holes, giants and supergiants, with physically consistent mass, radius, temperature and luminosity. |
| `Bodies.swift` | Planets, moons, rings and belts: orbits, temperature, gravity, atmosphere, habitable zone, and whether you can land (2.0 airless, 3.0 thin atmosphere). Sol is hand-built from real data. |
| `Settlement.swift` | Human space spreading out from Earth: population, economy, security and named stations. |
| `Naming.swift` | Region names and unique system designations ("Zybelval DX-20100 1"). |
| `Galaxy.swift` | The API: find systems, get full detail, plot routes. Stable 64-bit `SystemID`s for saves. |
| `GalaxyMap.swift` | Renders the top-down galaxy image used for the galaxy map. |

## Using it in the app

Add the folder to your Xcode project as a local package (File → Add Package Dependencies →
Add Local…), then:

```swift
import StarfallGalaxy

let galaxy = Galaxy()                                   // default seed

// What's around the player?
let nearby = galaxy.systems(within: 20, of: .sol)       // nearest first

// Open a system: stars, planets, moons, stations. Under a millisecond.
if let sol = galaxy.system(galaxy.sol.id) {
    print(sol.bodies.map(\.name))                       // Mercury, Venus, Earth, Mars, ...
}

// Plot a route with a 7.5 ly jump range.
let tauCeti = galaxy.system(named: "Tau Ceti")!
let path = galaxy.route(from: galaxy.sol.id, to: tauCeti.id, jumpRange: 7.5)

// Save games store the ID, never an array index.
let saved = tauCeti.id.description                       // "#8000000000000013"
let restored = SystemID(string: saved)
```

`Galaxy` is a value type and `Sendable`: generate on a background task and hand results to
the UI. Nothing is cached inside it, so keep a small cache of recently opened systems in the app.

## Command-line explorer

```
swift run -c release galaxy-cli stats
swift run -c release galaxy-cli near Sol 15
swift run -c release galaxy-cli system "Alpha Centauri"
swift run -c release galaxy-cli route Sol Betelgeuse 40
swift run -c release galaxy-cli map galaxy.ppm 1024
swift run -c release galaxy-cli export galaxy.json 25 60
```

## Tests

`swift test` runs 14 tests: same seed gives the same galaxy, summaries agree with full
detail, IDs round-trip, Sol and its planets are correct, real stars point the right way
in the sky (checked against published galactic coordinates), no invented stars inside the
catalogued bubble, local density matches the solar neighbourhood, human space thins with
distance, routes respect jump range, and the map renders with Sol in frame.

## Measured output (default seed)

- About 113 billion systems in the galaxy
- 109 systems within 20 ly (astronomers count about 110), 1,716 within 50 ly
- 25,306 populated systems within 250 ly of Earth
- Sol → Betelgeuse (548 ly) at 40 ly jump range: 15 jumps, about 3 s to plot

## Things to know

- **Real star data is approximate.** Positions, masses and exoplanet values were entered
  from published figures and are accurate enough for gameplay, but should be replaced or
  extended with a proper catalogue import (for example the HYG database, built from
  Hipparcos and Gaia, CC BY-SA) before release, with attribution in the credits.
- **Determinism across devices.** Star counts and positions use only basic arithmetic,
  and density is quantised before counts are drawn, so generation is stable. Planet
  details use `pow`/`log`, which can differ in the last digit between platforms; that
  only matters if you compare results between an iPad and a Linux test machine.
- **Long routes are slow-ish.** A 500 ly route takes a few seconds. Before 1.0, add a
  neighbour cache and run the planner on a background task with a progress indicator.
- **Stellar rarity is tuned for play.** Within 100 ly expect about 20 B stars, a few
  neutron stars and usually no black holes, so remnants stay worth finding.

## Next steps

1. Hook `GalaxyMapRenderer` output up as the galaxy-map texture in RealityKit.
2. Add factions and commodity markets on top of `Settlement`.
3. Import a full real-star catalogue for the region around Sol.
