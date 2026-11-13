import Foundation

/// A stable identifier for every star system. Save files store this, never array indices.
///
/// - Catalogued systems: top bit set, low bits hold the catalogue index.
/// - Procedural systems: 16 bits each for the cell's x, y and z (offset by 32,768), and
///   15 bits for the system's index within its cell.
public struct SystemID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    static let catalogueFlag: UInt64 = 1 << 63

    static func catalogue(_ index: Int) -> SystemID {
        SystemID(rawValue: catalogueFlag | UInt64(index))
    }

    static func procedural(cell: CellCoordinate, index: Int) -> SystemID? {
        guard Galaxy.cellRange.contains(cell.x), Galaxy.cellRange.contains(cell.y),
              Galaxy.cellRange.contains(cell.z), index >= 0, index < 1 << 15 else { return nil }
        let x = UInt64(Int64(cell.x) + 32_768), y = UInt64(Int64(cell.y) + 32_768), z = UInt64(Int64(cell.z) + 32_768)
        return SystemID(rawValue: (x << 47) | (y << 31) | (z << 15) | UInt64(index))
    }

    public var isCatalogued: Bool { rawValue & SystemID.catalogueFlag != 0 }

    var catalogueIndex: Int? {
        isCatalogued ? Int(rawValue & ~SystemID.catalogueFlag) : nil
    }

    var cellAndIndex: (CellCoordinate, Int)? {
        guard !isCatalogued else { return nil }
        let x = Int32(Int64((rawValue >> 47) & 0xFFFF) - 32_768)
        let y = Int32(Int64((rawValue >> 31) & 0xFFFF) - 32_768)
        let z = Int32(Int64((rawValue >> 15) & 0xFFFF) - 32_768)
        return (CellCoordinate(x: x, y: y, z: z), Int(rawValue & 0x7FFF))
    }

    public var description: String { String(format: "#%016llX", rawValue) }

    /// Parses the "#0123ABCD..." form produced by `description`.
    public init?(string: String) {
        let hex = string.hasPrefix("#") ? String(string.dropFirst()) : string
        guard let v = UInt64(hex, radix: 16) else { return nil }
        rawValue = v
    }
}

/// What the galaxy map and route planner need to know about a system. Cheap to generate.
public struct SystemSummary: Codable, Sendable, Hashable, Identifiable {
    public var id: SystemID
    public var name: String
    public var position: GalacticPosition
    public var primaryClass: StellarClass
    public var primarySpectralType: String
    public var starCount: Int
    public var isPopulated: Bool
    public var isCatalogued: Bool

    public var distanceFromSol: Double { position.distance(to: .sol) }
}

/// Everything about a system: stars, planets, moons, belts and who lives there.
public struct StarSystem: Codable, Sendable {
    public var summary: SystemSummary
    public var stars: [Star]
    public var bodies: [Body]
    public var settlement: Settlement?

    public var name: String { summary.name }
    public var id: SystemID { summary.id }
}

/// The galaxy: a deterministic function from a seed to every star system in the Milky Way.
///
/// Nothing is stored. Ask for a region and its systems are generated on the spot,
/// identically every time. The app should cache what it has recently shown.
public struct Galaxy: Sendable {
    public static let defaultSeed: UInt64 = 0x57A2_FA11_D21F_7001
    static let cellRange: ClosedRange<Int32> = -32_000...32_000

    public let seed: UInt64
    public let density: DensityModel

    public init(seed: UInt64 = Galaxy.defaultSeed) {
        self.seed = seed
        density = DensityModel(seed: seed)
    }

    // MARK: - Finding systems

    /// All systems within `radius` light-years of `centre`, nearest first.
    public func systems(within radius: Double, of centre: GalacticPosition, limit: Int? = nil) -> [SystemSummary] {
        let r2 = radius * radius
        var found: [SystemSummary] = []
        for (i, entry) in StarCatalogue.entries.enumerated() where entry.position.distanceSquared(to: centre) <= r2 {
            found.append(catalogueSummary(i))
        }
        let lo = CellCoordinate(containing: GalacticPosition(x: centre.x - radius, y: centre.y - radius, z: centre.z - radius))
        let hi = CellCoordinate(containing: GalacticPosition(x: centre.x + radius, y: centre.y + radius, z: centre.z + radius))
        for x in lo.x...hi.x {
            for y in lo.y...hi.y {
                for z in lo.z...hi.z {
                    let cell = CellCoordinate(x: x, y: y, z: z)
                    guard cell.minimumDistanceSquared(to: centre) <= r2 else { continue }
                    for (id, position) in cellSystems(cell) where position.distanceSquared(to: centre) <= r2 {
                        found.append(proceduralSummary(id: id, position: position))
                    }
                }
            }
        }
        found.sort { $0.position.distanceSquared(to: centre) < $1.position.distanceSquared(to: centre) }
        if let limit, found.count > limit { found.removeLast(found.count - limit) }
        return found
    }

    /// Looks up a catalogued system by name, case-insensitively ("sol", "Alpha Centauri").
    public func system(named name: String) -> SystemSummary? {
        guard let i = StarCatalogue.nameIndex[name.lowercased()] else { return nil }
        return catalogueSummary(i)
    }

    public var sol: SystemSummary { catalogueSummary(0) }

    /// Every catalogued (real) system, in catalogue order.
    public var catalogue: [SystemSummary] { StarCatalogue.entries.indices.map(catalogueSummary) }

    public func summary(for id: SystemID) -> SystemSummary? {
        if let i = id.catalogueIndex {
            return i < StarCatalogue.entries.count ? catalogueSummary(i) : nil
        }
        guard let (cell, index) = id.cellAndIndex else { return nil }
        guard let match = cellSystems(cell).first(where: { $0.0 == id }) else { return nil }
        _ = index
        return proceduralSummary(id: match.0, position: match.1)
    }

    // MARK: - System detail

    /// Full detail for one system. Generated on demand (fast: well under a millisecond).
    public func system(_ id: SystemID) -> StarSystem? {
        guard let summary = summary(for: id) else { return nil }
        if let i = id.catalogueIndex { return catalogueSystem(i, summary: summary) }
        return proceduralSystem(summary)
    }

    // MARK: - Cells

    /// Positions of the procedural systems in one 10 ly cell.
    func cellSystems(_ cell: CellCoordinate) -> [(SystemID, GalacticPosition)] {
        guard Galaxy.cellRange.contains(cell.x), Galaxy.cellRange.contains(cell.y), Galaxy.cellRange.contains(cell.z) else { return [] }
        let centre = cell.centre
        let complete = StarCatalogue.completeRadiusLY
        if centre.distance(to: .sol) < complete - 9 { return [] }   // fully inside the catalogued bubble

        // Quantised so tiny floating-point differences between devices can't change counts.
        let lambda = (density.systemsPerCubicLY(at: centre) * pow(CellCoordinate.size, 3) * 4_096).rounded() / 4_096
        var rng = SplitMix64(seed: SplitMix64.hash(seed, 0xCE11,
                                                   UInt64(bitPattern: Int64(cell.x)), UInt64(bitPattern: Int64(cell.y)),
                                                   UInt64(bitPattern: Int64(cell.z))))
        let count = min(rng.starCount(expected: lambda), 32_767)
        let origin = cell.origin
        var result: [(SystemID, GalacticPosition)] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            let p = GalacticPosition(x: origin.x + rng.unit() * CellCoordinate.size,
                                     y: origin.y + rng.unit() * CellCoordinate.size,
                                     z: origin.z + rng.unit() * CellCoordinate.size)
            if p.distance(to: .sol) < complete { continue }
            if let id = SystemID.procedural(cell: cell, index: i) { result.append((id, p)) }
        }
        return result
    }

    // MARK: - Procedural generation

    /// The first draws from a system's generator. Summary and detail share them, so a
    /// summary always agrees with the full system.
    private struct Opening {
        var primaryClass: StellarClass
        var luminosity: LuminosityClass
        var subclass: Double
        var companions: Int
        var populatedRoll: Double
    }

    private func opening(rng: inout SplitMix64, env: StellarEnvironment) -> Opening {
        let (cls, lum) = StarFactory.primaryClass(env, rng: &rng)
        let subclass = Double(rng.int(0...9))
        var companions = 0
        if rng.chance(StarFactory.companionChance(cls)) { companions = rng.chance(0.2) ? 2 : 1 }
        return Opening(primaryClass: cls, luminosity: lum, subclass: subclass, companions: companions, populatedRoll: rng.unit())
    }

    private func systemRNG(_ id: SystemID) -> SplitMix64 {
        SplitMix64(seed: SplitMix64.hash(seed, id.rawValue))
    }

    private func proceduralSummary(id: SystemID, position: GalacticPosition) -> SystemSummary {
        var rng = systemRNG(id)
        let env = StellarEnvironment(density.components(at: position))
        let o = opening(rng: &rng, env: env)
        let (cell, index) = id.cellAndIndex!
        let name = Naming.designation(seed: seed, cell: cell, index: index)
        let spectral = Star(name: name, stellarClass: o.primaryClass, subclass: o.subclass, luminosityClass: o.luminosity,
                            massSolar: 0, radiusSolar: 0, temperatureK: 0, luminositySolar: 0, separationAU: 0).spectralType
        let populated = SettlementModel.isPopulated(distanceFromSol: position.distance(to: .sol), primary: o.primaryClass,
                                                    catalogue: false, roll: o.populatedRoll)
        return SystemSummary(id: id, name: name, position: position, primaryClass: o.primaryClass,
                             primarySpectralType: spectral, starCount: 1 + o.companions,
                             isPopulated: populated, isCatalogued: false)
    }

    private func proceduralSystem(_ summary: SystemSummary) -> StarSystem {
        var rng = systemRNG(summary.id)
        let env = StellarEnvironment(density.components(at: summary.position))
        let o = opening(rng: &rng, env: env)
        let multiple = o.companions > 0
        let letters = ["A", "B", "C"]

        var stars = [Star.make(name: multiple ? "\(summary.name) A" : summary.name, cls: o.primaryClass,
                               subclass: o.subclass, lum: o.luminosity, separationAU: 0, rng: &rng)]
        for c in 0..<o.companions {
            let cls = StarFactory.companionClass(primary: o.primaryClass, rng: &rng)
            let sep = rng.logUniform(0.05, 5_000)
            stars.append(Star.make(name: "\(summary.name) \(letters[c + 1])", cls: cls, subclass: Double(rng.int(0...9)),
                                   lum: cls.isMainSequenceKind ? .mainSequence : .none, separationAU: sep, rng: &rng))
        }
        let bodies = buildBodies(systemName: summary.name, stars: stars, known: [], rng: &rng)
        let settlement = summary.isPopulated
            ? SettlementModel.build(system: summary.name, distanceFromSol: summary.distanceFromSol, bodies: bodies,
                                    isSol: false, rng: &rng)
            : nil
        return StarSystem(summary: summary, stars: stars, bodies: bodies, settlement: settlement)
    }

    // MARK: - Catalogue systems

    private func catalogueSummary(_ i: Int) -> SystemSummary {
        let e = StarCatalogue.entries[i]
        let id = SystemID.catalogue(i)
        var rng = systemRNG(id)
        let first = e.stars[0]
        let spectral = Star(name: e.name, stellarClass: first.stellarClass, subclass: first.subclass,
                            luminosityClass: first.luminosityClass, massSolar: 0, radiusSolar: 0, temperatureK: 0,
                            luminositySolar: 0, separationAU: 0).spectralType
        let populated = SettlementModel.isPopulated(distanceFromSol: e.position.distance(to: .sol),
                                                    primary: first.stellarClass, catalogue: true, roll: rng.unit())
        return SystemSummary(id: id, name: e.name, position: e.position, primaryClass: first.stellarClass,
                             primarySpectralType: spectral, starCount: e.stars.count,
                             isPopulated: i == 0 || populated, isCatalogued: true)
    }

    private func catalogueSystem(_ i: Int, summary: SystemSummary) -> StarSystem {
        let e = StarCatalogue.entries[i]
        var rng = systemRNG(summary.id)
        _ = rng.unit()  // the populated roll used by the summary
        var stars: [Star] = []
        for cs in e.stars {
            let name: String
            if cs.suffix.isEmpty { name = e.name }
            else if cs.suffix.count <= 2 { name = "\(e.name) \(cs.suffix)" }
            else { name = cs.suffix }
            var s = Star.make(name: name, cls: cs.stellarClass, subclass: cs.subclass, lum: cs.luminosityClass,
                              separationAU: cs.separationAU, rng: &rng)
            if let m = cs.massSolar { s.massSolar = m }
            if let r = cs.radiusSolar { s.radiusSolar = r }
            if let t = cs.temperatureK { s.temperatureK = t }
            if s.stellarClass != .blackHole && s.stellarClass != .neutronStar {
                s.luminositySolar = s.radiusSolar * s.radiusSolar * pow(s.temperatureK / 5_772, 4)
            }
            stars.append(s)
        }
        let isSol = i == 0
        let bodies = isSol ? SolSystem.bodies() : buildBodies(systemName: e.name, stars: stars, known: e.knownPlanets, rng: &rng)
        let settlement = summary.isPopulated
            ? SettlementModel.build(system: e.name, distanceFromSol: summary.distanceFromSol, bodies: bodies,
                                    isSol: isSol, rng: &rng)
            : nil
        return StarSystem(summary: summary, stars: stars, bodies: bodies, settlement: settlement)
    }

    // MARK: - Planets for multi-star systems

    private func buildBodies(systemName: String, stars: [Star], known: [KnownPlanet], rng: inout SplitMix64) -> [Body] {
        var bodies: [Body] = []
        // Close companions (under 100 AU) carve a gap in the primary's planets.
        let close = stars.dropFirst().map(\.separationAU).filter { $0 < 100 }.min()
        let gap = close.map { ($0 * 0.33)...($0 * 3) }
        for (index, star) in stars.enumerated() {
            if index > 0 && star.separationAU < 100 { continue }   // too close for its own planets
            let prefix = stars.count == 1 ? systemName : star.name
            let k = known.filter { $0.hostStar == index }
            bodies += BodyFactory.planets(around: star, hostIndex: index, systemName: systemName, namePrefix: prefix,
                                          known: k, companionGapAU: index == 0 ? gap : nil, rng: &rng)
        }
        return bodies
    }

    // MARK: - Routes

    /// Plots a short route (in jumps) between two systems with a given jump range.
    ///
    /// Uses weighted A*: `greed` above 1 trades a little optimality for much faster
    /// searches on long trips. Returns nil when no route exists within the search budget.
    public func route(from start: SystemID, to goal: SystemID, jumpRange: Double,
                      greed: Double = 1.25, maxExpansions: Int = 20_000) -> [SystemSummary]? {
        guard let a = summary(for: start), let b = summary(for: goal), jumpRange > 0 else { return nil }
        if a.id == b.id { return [a] }

        var open = MinHeap<SystemID>()
        open.push(a.position.distance(to: b.position) / jumpRange * greed, a.id)
        var g: [SystemID: Double] = [a.id: 0]
        var cameFrom: [SystemID: SystemID] = [:]
        var known: [SystemID: SystemSummary] = [a.id: a, b.id: b]
        var closed = Set<SystemID>()
        var expansions = 0

        while let current = open.pop(), expansions < maxExpansions {
            if current == b.id {
                var path = [b]
                var c = b.id
                while let p = cameFrom[c] {
                    path.append(known[p]!)
                    c = p
                }
                return path.reversed()
            }
            if closed.contains(current) { continue }
            closed.insert(current)
            expansions += 1
            let here = known[current]!
            var neighbours = systems(within: jumpRange, of: here.position)
            if here.position.distance(to: b.position) <= jumpRange && !neighbours.contains(where: { $0.id == b.id }) {
                neighbours.append(b)
            }
            for n in neighbours where n.id != current && !closed.contains(n.id) {
                known[n.id] = n
                // One jump each, plus a small distance term so shorter hops win ties.
                let cost = g[current]! + 1 + here.position.distance(to: n.position) / (jumpRange * 100)
                if cost < g[n.id] ?? .infinity {
                    g[n.id] = cost
                    cameFrom[n.id] = current
                    let h = n.position.distance(to: b.position) / jumpRange
                    open.push(cost + h * greed, n.id)
                }
            }
        }
        return nil
    }
}

/// A small binary heap keyed by priority, used by the route planner.
struct MinHeap<Element> {
    private var items: [(priority: Double, element: Element)] = []

    var isEmpty: Bool { items.isEmpty }

    mutating func push(_ priority: Double, _ element: Element) {
        items.append((priority, element))
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            if items[parent].priority <= items[i].priority { break }
            items.swapAt(parent, i)
            i = parent
        }
    }

    mutating func pop() -> Element? {
        guard !items.isEmpty else { return nil }
        items.swapAt(0, items.count - 1)
        let top = items.removeLast()
        var i = 0
        while true {
            let l = 2 * i + 1, r = l + 1
            var smallest = i
            if l < items.count && items[l].priority < items[smallest].priority { smallest = l }
            if r < items.count && items[r].priority < items[smallest].priority { smallest = r }
            if smallest == i { break }
            items.swapAt(i, smallest)
            i = smallest
        }
        return top.element
    }
}
