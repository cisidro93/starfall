import Foundation

public enum Economy: String, Codable, Sendable, CaseIterable {
    case highTech = "High tech"
    case industrial = "Industrial"
    case agriculture = "Agriculture"
    case extraction = "Extraction"
    case refinery = "Refinery"
    case tourism = "Tourism"
    case military = "Military"
    case colony = "Colony"
}

public enum Security: String, Codable, Sendable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    case anarchy = "Anarchy"
}

public enum StationType: String, Codable, Sendable {
    case ring = "Ring station"            // large rotating habitat, all ship sizes
    case spoke = "Spoke station"          // mid-size, medium ships
    case outpost = "Outpost"              // small, light ships
    case surfacePort = "Surface port"     // on a landable body (2.0)
}

public struct Station: Codable, Sendable, Hashable {
    public var name: String
    public var type: StationType
    public var orbiting: String
}

public struct Settlement: Codable, Sendable, Hashable {
    public var population: Int64
    public var economy: Economy
    public var secondaryEconomy: Economy?
    public var security: Security
    public var stations: [Station]
    public var isCapital: Bool
}

/// Human space spreads outward from Sol: dense and secure near Earth, thinning into a
/// lawless frontier a few hundred light-years out. Everything beyond is unexplored.
public enum SettlementModel {
    /// Distance at which the chance of a populated system has fallen to about 37% of its peak.
    public static let reachLY = 140.0
    /// Catalogued stars within this distance are always populated.
    public static let catalogueCoreLY = 30.0

    /// Cheap check used for summaries and the galaxy map.
    static func isPopulated(distanceFromSol d: Double, primary: StellarClass, catalogue: Bool, roll: Double) -> Bool {
        if catalogue && d <= catalogueCoreLY { return true }
        if d > 450 { return false }
        var p = 0.6 * exp(-pow(d / reachLY, 2))
        if primary.isRemnant || primary.isBrownDwarf { p *= 0.3 }
        if primary == .O || primary == .B { p *= 0.5 }
        if catalogue { p = max(p, 0.5) }
        return roll < p
    }

    static let surnames = [
        "Kepler", "Hubble", "Leavitt", "Galilei", "Herschel", "Curie", "Tereshkova", "Gagarin", "Armstrong",
        "Ride", "Jemison", "Sagan", "Payne", "Rubin", "Lovelace", "Hopper", "Tsiolkovsky", "Goddard", "Oberth",
        "Korolev", "Noether", "Ramanujan", "Meitner", "Bose", "Chandrasekhar", "Brahe", "Copernicus", "Huygens",
        "Cassini", "Messier", "Halley", "Lagrange", "Euler", "Gauss", "Fermi", "Feynman", "Hawking",
        "Bell Burnell", "Katherine Johnson", "Vaughan", "Mary Jackson", "Shepard", "Glenn", "Aldrin", "Collins",
        "Leonov", "Chawla", "Hadfield", "Peake", "Ochoa", "Yang Liwei", "Nagata", "Somerville", "Cannon",
        "Fleming", "Tombaugh", "Hale", "Lowell", "Banneker", "Al-Sufi", "Ulugh Beg", "Hypatia", "Aryabhata",
        "Zhang Heng", "Ptolemy", "Hipparchus", "Eratosthenes", "Bessel", "Struve", "Kuiper", "Oort", "Drake",
    ]
    static let stationSuffixes = ["Station", "Port", "Hub", "Ring", "Terminal", "Orbital", "Dock", "Gateway", "Landing"]

    static func build(system name: String, distanceFromSol d: Double, bodies: [Body], isSol: Bool,
                      rng: inout SplitMix64) -> Settlement {
        let flat = bodies.flatMap { [$0] + $0.moons }
        let hasEarthLike = flat.contains { $0.kind == .earthLike }
        let hasWater = flat.contains { $0.kind == .waterWorld }
        let giants = flat.filter { $0.kind.isGiant }.count
        let landable = flat.filter { $0.landing != .notLandable }.count

        // Population falls off with distance; garden worlds support far more people.
        var logPop = 9.6 - d / 45 + rng.uniform(-0.8, 0.8)
        if hasEarthLike { logPop += 1.5 }
        if hasWater { logPop += 0.5 }
        logPop = min(11, max(3, logPop))
        var population = Int64(pow(10, logPop))
        if isSol { population = 22_000_000_000 }

        var options: [(Economy, Double)] = [(.colony, d > 120 ? 2.5 : 0.4)]
        if hasEarthLike { options += [(.agriculture, 2.5), (.highTech, 1.5), (.tourism, 0.8)] }
        if hasWater { options += [(.agriculture, 1), (.tourism, 1)] }
        if landable > 2 { options.append((.extraction, Double(landable) * 0.4)) }
        if giants > 0 { options.append((.refinery, Double(giants) * 0.6)) }
        options += [(.industrial, d < 80 ? 1.5 : 0.6), (.highTech, d < 40 ? 1.2 : 0.3), (.military, 0.25)]
        let primary = options[rng.weightedIndex(options.map(\.1))].0
        let rest = options.filter { $0.0 != primary }
        let secondary: Economy? = (!rest.isEmpty && rng.chance(0.5)) ? rest[rng.weightedIndex(rest.map(\.1))].0 : nil

        let security: Security
        if d < 40 { security = .high }
        else if d < 120 { security = rng.chance(0.75) ? .medium : .high }
        else if rng.chance(0.15) { security = .anarchy }
        else { security = rng.chance(0.6) ? .low : .medium }

        // Stations orbit the most promising bodies.
        let stationCount = isSol ? 6 : max(1, min(8, Int(logPop) - 4 + rng.int(0...1)))
        var anchors = flat.filter { $0.kind != .asteroidBelt }
            .sorted { score($0) > score($1) }
        if anchors.isEmpty { anchors = [] }
        var stations: [Station] = []
        var usedNames = Set<String>()
        for i in 0..<stationCount {
            var stationName: String
            repeat {
                stationName = "\(surnames[rng.int(0...(surnames.count - 1))]) \(stationSuffixes[rng.int(0...(stationSuffixes.count - 1))])"
            } while usedNames.contains(stationName)
            usedNames.insert(stationName)
            let anchor = anchors.isEmpty ? "\(name) star" : anchors[i % anchors.count].name
            let anchorBody = anchors.isEmpty ? nil : anchors[i % anchors.count]
            let type: StationType
            if let body = anchorBody, body.landing != .notLandable, rng.chance(0.3) { type = .surfacePort }
            else if i == 0 && logPop > 7 { type = .ring }
            else { type = [StationType.ring, .spoke, .outpost][rng.weightedIndex([logPop > 8 ? 1 : 0.2, 1, 1.2])] }
            stations.append(Station(name: stationName, type: type, orbiting: anchor))
        }
        if isSol {
            stations[0] = Station(name: "Gagarin Gateway", type: .ring, orbiting: "Earth")
            stations[1] = Station(name: "Armstrong Landing", type: .surfacePort, orbiting: "Moon")
            stations[2] = Station(name: "Tsiolkovsky Ring", type: .ring, orbiting: "Mars")
        }

        return Settlement(population: population, economy: isSol ? .highTech : primary,
                          secondaryEconomy: isSol ? .industrial : secondary, security: security,
                          stations: stations, isCapital: isSol)
    }

    private static func score(_ b: Body) -> Double {
        switch b.kind {
        case .earthLike: return 10
        case .waterWorld: return 6
        case .gasGiant, .iceGiant: return 4
        default: return b.landing != .notLandable ? 3 : 1
        }
    }
}
