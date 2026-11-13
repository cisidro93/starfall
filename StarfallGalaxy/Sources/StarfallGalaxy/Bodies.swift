import Foundation

public enum BodyKind: String, Codable, Sendable {
    case rocky = "Rocky world"
    case metalRich = "Metal-rich world"
    case icy = "Icy world"
    case waterWorld = "Water world"
    case earthLike = "Earth-like world"
    case gasGiant = "Gas giant"
    case iceGiant = "Ice giant"
    case dwarfPlanet = "Dwarf planet"
    case asteroidBelt = "Asteroid belt"

    public var isGiant: Bool { self == .gasGiant || self == .iceGiant }
}

public enum Atmosphere: String, Codable, Sendable {
    case none = "None"
    case thin = "Thin"
    case breathable = "Breathable"
    case thick = "Thick"
    case hydrogenHelium = "Hydrogen-helium"
}

/// Which release can land here: airless worlds come with the surface update (2.0),
/// thin atmospheres with the frontier update (3.0).
public enum Landing: String, Codable, Sendable {
    case notLandable = "Not landable"
    case airless = "Landable (airless)"
    case thinAtmosphere = "Landable (thin atmosphere)"
}

public struct Body: Codable, Sendable, Hashable {
    public var name: String
    public var kind: BodyKind
    /// Index into the system's `stars` array.
    public var hostStar: Int
    /// Orbit around the parent (star for planets, planet for moons).
    public var semiMajorAxisKm: Double
    public var radiusKm: Double
    public var massEarth: Double
    public var surfaceGravityG: Double
    public var temperatureK: Double
    public var atmosphere: Atmosphere
    public var hasRings: Bool
    public var landing: Landing
    public var isInHabitableZone: Bool
    /// True for real, catalogued bodies (Sol's planets, confirmed exoplanets).
    public var isCatalogued: Bool
    public var moons: [Body]

    public static let kmPerAU = 149_597_870.7
    public var semiMajorAxisAU: Double { semiMajorAxisKm / Body.kmPerAU }
}

enum BodyFactory {
    static let earthRadiusKm = 6_371.0

    static func gravity(massEarth: Double, radiusKm: Double) -> Double {
        guard radiusKm > 0 else { return 0 }
        let r = radiusKm / earthRadiusKm
        return massEarth / (r * r)
    }

    static func equilibriumTemperature(luminosity: Double, au: Double) -> Double {
        guard au > 0 else { return 0 }
        return 278.6 * pow(max(luminosity, 1e-9), 0.25) / au.squareRoot() * 0.915
    }

    /// Builds the planets, belts and moons around one star.
    static func planets(around star: Star, hostIndex: Int, systemName: String, namePrefix: String,
                        known: [KnownPlanet], companionGapAU: ClosedRange<Double>?,
                        rng: inout SplitMix64) -> [Body] {
        let lum = max(star.luminositySolar, 1e-6)
        let rootL = lum.squareRoot()
        let snowLine = 2.7 * rootL
        let hzInner = 0.95 * rootL, hzOuter = 1.67 * rootL
        let starRadiusAU = star.radiusSolar * 0.00465
        let minimumAU = max(starRadiusAU * 4, 0.004)

        var bodies: [Body] = []
        var usedLetters = Set<Character>()

        func makeName(_ suffix: String) -> String { "\(namePrefix) \(suffix)" }

        // Confirmed exoplanets first, at their measured orbits.
        for k in known {
            let temp = equilibriumTemperature(luminosity: lum, au: k.semiMajorAxisAU)
            let kind: BodyKind = k.massEarth > 50 ? .gasGiant : (k.massEarth > 10 ? .iceGiant : (temp < 150 ? .icy : .rocky))
            var b = body(kind: kind, mass: k.massEarth, au: k.semiMajorAxisAU, temp: temp, host: hostIndex,
                         name: makeName(k.suffix), hz: (hzInner...hzOuter).contains(k.semiMajorAxisAU), rng: &rng)
            b.isCatalogued = true
            bodies.append(b)
            if let c = k.suffix.last { usedLetters.insert(c) }
        }

        // Then procedural planets, starting beyond the outermost confirmed planet.
        let count = plannedPlanetCount(star, rng: &rng)
        var au: Double
        if let outer = known.map(\.semiMajorAxisAU).max() {
            au = outer * rng.uniform(1.5, 2.2)
        } else {
            au = rng.uniform(0.02, 0.25) * max(0.15, rootL)
        }
        au = max(au, minimumAU)
        var letter: Character = "b"
        func nextLetter() -> String {
            while usedLetters.contains(letter) { letter = Character(UnicodeScalar(letter.asciiValue! + 1)) }
            let s = String(letter)
            usedLetters.insert(letter)
            return s
        }
        var beltNumber = 1
        for _ in 0..<count {
            if let gap = companionGapAU, gap.contains(au) {
                au = gap.upperBound * rng.uniform(1.1, 1.5)
            }
            if au > 2_000 { break }
            let temp = equilibriumTemperature(luminosity: lum, au: au)
            if rng.chance(0.12) {
                bodies.append(Body(name: "\(namePrefix) Belt \(beltNumber)", kind: .asteroidBelt, hostStar: hostIndex,
                                   semiMajorAxisKm: au * Body.kmPerAU, radiusKm: 0, massEarth: rng.logUniform(0.0002, 0.01),
                                   surfaceGravityG: 0, temperatureK: temp, atmosphere: .none, hasRings: false,
                                   landing: .notLandable, isInHabitableZone: false, isCatalogued: false, moons: []))
                beltNumber += 1
            } else {
                let kind = chooseKind(au: au, snowLine: snowLine, hz: hzInner...hzOuter, temp: temp, star: star, rng: &rng)
                let mass = massFor(kind, rng: &rng)
                let b = body(kind: kind, mass: mass, au: au, temp: temp, host: hostIndex,
                             name: makeName(nextLetter()), hz: (hzInner...hzOuter).contains(au), rng: &rng)
                bodies.append(b)
            }
            au *= rng.uniform(1.45, 2.1)
        }
        return bodies.sorted { $0.semiMajorAxisKm < $1.semiMajorAxisKm }
    }

    static func plannedPlanetCount(_ star: Star, rng: inout SplitMix64) -> Int {
        switch star.stellarClass {
        case .O, .B: return rng.int(0...3)
        case .A: return rng.int(0...6)
        case .F, .G, .K: return [rng.int(1...10), rng.int(2...9)].min()! + (rng.chance(0.3) ? 1 : 0)
        case .M: return rng.int(0...7)
        case .L, .T, .Y: return rng.int(0...3)
        case .whiteDwarf: return rng.int(0...2)
        case .neutronStar: return rng.chance(0.2) ? rng.int(1...2) : 0
        case .blackHole: return 0
        }
    }

    static func chooseKind(au: Double, snowLine: Double, hz: ClosedRange<Double>, temp: Double,
                           star: Star, rng: inout SplitMix64) -> BodyKind {
        let giantScale = min(1, star.massSolar / 0.5)
        if au > snowLine {
            let w = [0.35 * giantScale, 0.25 * max(0.4, giantScale), 0.3, 0.1]
            return [BodyKind.gasGiant, .iceGiant, .icy, .dwarfPlanet][rng.weightedIndex(w)]
        }
        var kinds: [BodyKind] = [.rocky, .metalRich, .gasGiant]
        var w: [Double] = [0.45, au < 0.2 * snowLine ? 0.35 : 0.15, 0.03]
        if temp > 180 && temp < 420 {
            kinds.append(.waterWorld)
            w.append(0.07)
        }
        if hz.contains(au) && star.stellarClass.isMainSequenceKind && star.luminosityClass == .mainSequence {
            kinds.append(.earthLike)
            switch star.stellarClass {
            case .G, .K: w.append(0.07)
            case .F, .M: w.append(0.025)
            default: w.append(0.005)
            }
        }
        return kinds[rng.weightedIndex(w)]
    }

    static func massFor(_ kind: BodyKind, rng: inout SplitMix64) -> Double {
        switch kind {
        case .rocky: return rng.logUniform(0.02, 2.5)
        case .metalRich: return rng.logUniform(0.03, 1.5)
        case .earthLike: return rng.uniform(0.5, 1.8)
        case .waterWorld: return rng.uniform(0.8, 6)
        case .icy: return rng.logUniform(0.0005, 0.8)
        case .dwarfPlanet: return rng.logUniform(0.0002, 0.01)
        case .gasGiant: return rng.logUniform(30, 4_000)
        case .iceGiant: return rng.uniform(8, 30)
        case .asteroidBelt: return rng.logUniform(0.0002, 0.01)
        }
    }

    static func radiusFor(_ kind: BodyKind, mass: Double) -> Double {
        let e = earthRadiusKm
        switch kind {
        case .rocky, .earthLike: return e * pow(mass, 0.28)
        case .metalRich: return e * 0.85 * pow(mass, 0.27)
        case .waterWorld: return e * 1.15 * pow(mass, 0.27)
        case .icy: return e * 1.25 * pow(mass, 0.3)
        case .dwarfPlanet: return e * 1.3 * pow(mass, 0.3)
        case .gasGiant: return 69_911 * min(1.1, max(0.55, pow(mass / 317.8, 0.45)))
        case .iceGiant: return 25_000 * pow(mass / 15, 0.3)
        case .asteroidBelt: return 0
        }
    }

    static func body(kind: BodyKind, mass: Double, au: Double, temp: Double, host: Int, name: String,
                     hz: Bool, rng: inout SplitMix64) -> Body {
        let radius = radiusFor(kind, mass: mass)
        var atmosphere: Atmosphere
        var surfaceTemp = temp
        switch kind {
        case .gasGiant, .iceGiant: atmosphere = .hydrogenHelium
        case .earthLike: atmosphere = .breathable; surfaceTemp += 33
        case .waterWorld: atmosphere = .thick; surfaceTemp += rng.uniform(20, 60)
        case .rocky, .metalRich:
            if mass < 0.1 || temp > 900 { atmosphere = .none }
            else {
                let roll = rng.unit()
                atmosphere = roll < 0.45 ? .none : (roll < 0.8 ? .thin : .thick)
            }
        case .icy: atmosphere = (mass > 0.01 && temp < 120 && rng.chance(0.25)) ? .thin : .none
        case .dwarfPlanet, .asteroidBelt: atmosphere = .none
        }
        if atmosphere == .thick && !kind.isGiant && kind != .waterWorld { surfaceTemp += rng.uniform(100, 450) }
        if atmosphere == .thin { surfaceTemp += rng.uniform(3, 20) }

        let g = gravity(massEarth: mass, radiusKm: radius)
        let landing: Landing
        switch atmosphere {
        case .none: landing = g < 3 ? .airless : .notLandable
        case .thin: landing = g < 3 ? .thinAtmosphere : .notLandable
        default: landing = .notLandable
        }

        var b = Body(name: name, kind: kind, hostStar: host, semiMajorAxisKm: au * Body.kmPerAU,
                     radiusKm: radius, massEarth: mass, surfaceGravityG: g, temperatureK: surfaceTemp,
                     atmosphere: atmosphere, hasRings: kind.isGiant ? rng.chance(0.35) : rng.chance(0.02),
                     landing: landing, isInHabitableZone: hz, isCatalogued: false, moons: [])
        b.moons = moons(for: b, temp: temp, rng: &rng)
        return b
    }

    static let romanNumerals = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

    static func moons(for planet: Body, temp: Double, rng: inout SplitMix64) -> [Body] {
        let count: Int
        switch planet.kind {
        case .gasGiant: count = min(rng.int(0...8), rng.int(1...8))
        case .iceGiant: count = rng.int(0...5)
        case .earthLike: count = rng.chance(0.4) ? 1 : 0
        case .rocky, .metalRich, .waterWorld: count = rng.chance(0.25) ? rng.int(1...2) : 0
        default: count = 0
        }
        var result: [Body] = []
        var orbit = max(planet.radiusKm, 1_000) * rng.uniform(3, 6)
        for i in 0..<count {
            let kind: BodyKind = temp < 160 ? (rng.chance(0.7) ? .icy : .rocky) : (rng.chance(0.75) ? .rocky : .metalRich)
            let maxMass = min(planet.massEarth * 0.02, 0.05)
            let mass = rng.logUniform(min(0.00005, maxMass * 0.5), max(maxMass, 0.0001))
            let radius = radiusFor(kind, mass: mass)
            let g = gravity(massEarth: mass, radiusKm: radius)
            let atmosphere: Atmosphere = (mass > 0.01 && rng.chance(0.1)) ? .thin : .none
            let landing: Landing = atmosphere == .thin ? .thinAtmosphere : .airless
            result.append(Body(name: "\(planet.name) \(romanNumerals[min(i, 9)])", kind: kind,
                               hostStar: planet.hostStar, semiMajorAxisKm: orbit, radiusKm: radius,
                               massEarth: mass, surfaceGravityG: g, temperatureK: temp, atmosphere: atmosphere,
                               hasRings: false, landing: landing, isInHabitableZone: planet.isInHabitableZone,
                               isCatalogued: false, moons: []))
            orbit *= rng.uniform(1.4, 2.0)
        }
        return result
    }
}

/// Sol, built by hand from real data.
enum SolSystem {
    static func bodies() -> [Body] {
        func moon(_ name: String, km: Double, r: Double, m: Double, t: Double, _ kind: BodyKind = .rocky,
                  atm: Atmosphere = .none) -> Body {
            let g = BodyFactory.gravity(massEarth: m, radiusKm: r)
            return Body(name: name, kind: kind, hostStar: 0, semiMajorAxisKm: km, radiusKm: r, massEarth: m,
                        surfaceGravityG: g, temperatureK: t, atmosphere: atm, hasRings: false,
                        landing: atm == .none ? .airless : (atm == .thin ? .thinAtmosphere : .notLandable),
                        isInHabitableZone: false, isCatalogued: true, moons: [])
        }
        func planet(_ name: String, au: Double, r: Double, m: Double, t: Double, _ kind: BodyKind,
                    atm: Atmosphere, rings: Bool = false, hz: Bool = false, moons: [Body] = []) -> Body {
            let g = BodyFactory.gravity(massEarth: m, radiusKm: r)
            let landing: Landing
            switch atm {
            case .none: landing = .airless
            case .thin: landing = .thinAtmosphere
            default: landing = .notLandable
            }
            return Body(name: name, kind: kind, hostStar: 0, semiMajorAxisKm: au * Body.kmPerAU, radiusKm: r,
                        massEarth: m, surfaceGravityG: g, temperatureK: t, atmosphere: atm, hasRings: rings,
                        landing: landing, isInHabitableZone: hz, isCatalogued: true, moons: moons)
        }
        return [
            planet("Mercury", au: 0.387, r: 2_440, m: 0.0553, t: 440, .metalRich, atm: .none),
            planet("Venus", au: 0.723, r: 6_052, m: 0.815, t: 737, .rocky, atm: .thick),
            planet("Earth", au: 1.000, r: 6_371, m: 1.0, t: 288, .earthLike, atm: .breathable, hz: true, moons: [
                moon("Moon", km: 384_400, r: 1_737, m: 0.0123, t: 250),
            ]),
            planet("Mars", au: 1.524, r: 3_390, m: 0.107, t: 210, .rocky, atm: .thin, hz: true, moons: [
                moon("Phobos", km: 9_376, r: 11, m: 1.8e-9, t: 233),
                moon("Deimos", km: 23_463, r: 6, m: 2.5e-10, t: 233),
            ]),
            planet("Ceres", au: 2.77, r: 470, m: 0.00016, t: 168, .dwarfPlanet, atm: .none),
            planet("Jupiter", au: 5.203, r: 69_911, m: 317.8, t: 165, .gasGiant, atm: .hydrogenHelium, moons: [
                moon("Io", km: 421_700, r: 1_822, m: 0.015, t: 130),
                moon("Europa", km: 671_000, r: 1_561, m: 0.008, t: 102, .icy),
                moon("Ganymede", km: 1_070_400, r: 2_634, m: 0.025, t: 110, .icy),
                moon("Callisto", km: 1_882_700, r: 2_410, m: 0.018, t: 134, .icy),
            ]),
            planet("Saturn", au: 9.537, r: 58_232, m: 95.2, t: 134, .gasGiant, atm: .hydrogenHelium, rings: true, moons: [
                moon("Enceladus", km: 238_000, r: 252, m: 1.8e-5, t: 75, .icy),
                moon("Titan", km: 1_221_870, r: 2_575, m: 0.0225, t: 94, .icy, atm: .thick),
            ]),
            planet("Uranus", au: 19.19, r: 25_362, m: 14.5, t: 76, .iceGiant, atm: .hydrogenHelium, rings: true, moons: [
                moon("Titania", km: 436_300, r: 789, m: 0.00059, t: 70, .icy),
            ]),
            planet("Neptune", au: 30.07, r: 24_622, m: 17.1, t: 72, .iceGiant, atm: .hydrogenHelium, rings: true, moons: [
                moon("Triton", km: 354_800, r: 1_353, m: 0.00359, t: 38, .icy, atm: .thin),
            ]),
            planet("Pluto", au: 39.48, r: 1_188, m: 0.0022, t: 44, .dwarfPlanet, atm: .thin, moons: [
                moon("Charon", km: 19_591, r: 606, m: 0.00027, t: 53, .icy),
            ]),
        ]
    }
}
