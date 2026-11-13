import Foundation
import StarfallGalaxy

// A small explorer for the generated galaxy.
//
//   galaxy-cli stats
//   galaxy-cli near <system> [radius-ly]
//   galaxy-cli system <system>
//   galaxy-cli route <from> <to> <jump-range-ly>
//   galaxy-cli map <out.ppm> [size] [extent-ly]
//   galaxy-cli export <out.json> [detail-radius-ly] [summary-radius-ly]
//
// <system> is a catalogued name ("Sol", "Alpha Centauri") or an id like #0001F2...

let galaxy = Galaxy()
let args = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func resolve(_ text: String) -> SystemSummary {
    if let id = SystemID(string: text), text.hasPrefix("#"), let s = galaxy.summary(for: id) { return s }
    if let s = galaxy.system(named: text) { return s }
    fail("Unknown system: \(text)")
}

func ly(_ v: Double) -> String { String(format: "%.2f ly", v) }

func formatPopulation(_ p: Int64) -> String {
    let d = Double(p)
    if d >= 1e9 { return String(format: "%.1f billion", d / 1e9) }
    if d >= 1e6 { return String(format: "%.1f million", d / 1e6) }
    if d >= 1e3 { return String(format: "%.0f thousand", d / 1e3) }
    return "\(p)"
}

func printSystem(_ s: StarSystem) {
    print("\(s.name)  \(s.id)")
    print("  Position \(s.summary.position), \(ly(s.summary.distanceFromSol)) from Sol")
    for star in s.stars {
        let sep = star.separationAU > 0 ? String(format: ", %.1f AU from primary", star.separationAU) : ""
        print(String(format: "  ★ %@  %@  %.2f M☉  %.3g R☉  %.0f K  L=%.3g L☉%@",
                     star.name, star.spectralType, star.massSolar, star.radiusSolar, star.temperatureK,
                     star.luminositySolar, sep))
    }
    for b in s.bodies {
        printBody(b, indent: "  ")
    }
    if let st = s.settlement {
        let economy = st.secondaryEconomy.map { "\(st.economy.rawValue) / \($0.rawValue)" } ?? st.economy.rawValue
        print("  Population \(formatPopulation(st.population)), \(economy), security \(st.security.rawValue)\(st.isCapital ? ", capital" : "")")
        for station in st.stations {
            print("    ⌂ \(station.name) (\(station.type.rawValue)) — \(station.orbiting)")
        }
    } else {
        print("  Uninhabited")
    }
}

func printBody(_ b: Body, indent: String, isMoon: Bool = false) {
    if b.kind == .asteroidBelt {
        print(String(format: "%@○ %@  at %.2f AU", indent, b.name, b.semiMajorAxisAU))
        return
    }
    let orbit = isMoon ? String(format: "%.0f km", b.semiMajorAxisKm) : String(format: "%.3f AU", b.semiMajorAxisAU)
    var tags: [String] = []
    if b.isCatalogued { tags.append("real") }
    if b.isInHabitableZone { tags.append("habitable zone") }
    if b.hasRings { tags.append("rings") }
    if b.landing != .notLandable { tags.append(b.landing.rawValue.lowercased()) }
    let tagText = tags.isEmpty ? "" : "  [" + tags.joined(separator: ", ") + "]"
    print(String(format: "%@● %@  %@  %@  r=%.0f km  %.2f g  %.0f K  atm %@%@", indent, b.name, b.kind.rawValue,
                 orbit, b.radiusKm, b.surfaceGravityG, b.temperatureK, b.atmosphere.rawValue, tagText))
    for m in b.moons { printBody(m, indent: indent + "    ", isMoon: true) }
}

guard let command = args.first else {
    print("Commands: stats | near <system> [radius] | system <system> | route <from> <to> <range> | map <out.ppm> [size] [extent] | export <out.json> [detail-radius] [summary-radius]")
    exit(0)
}

switch command {
case "stats":
    let start = Date()
    let total = galaxy.density.estimatedTotalSystems()
    print(String(format: "Seed %016llX", galaxy.seed))
    print(String(format: "Density at Sol: %.4f systems/ly³", galaxy.density.systemsPerCubicLY(at: .sol)))
    print(String(format: "Estimated systems in the galaxy: %.1f billion (%.1fs)", total / 1e9, Date().timeIntervalSince(start)))
    for r in [20.0, 50.0, 100.0, 250.0] {
        let t0 = Date()
        let s = galaxy.systems(within: r, of: .sol)
        let populated = s.filter(\.isPopulated).count
        print(String(format: "Within %4.0f ly: %6d systems, %5d populated (%.2fs)", r, s.count, populated, Date().timeIntervalSince(t0)))
    }
    let counts = Dictionary(grouping: galaxy.systems(within: 100, of: .sol), by: \.primaryClass).mapValues(\.count)
    print("Primary star classes within 100 ly:")
    for cls in StellarClass.allCases where counts[cls] != nil {
        print("  \(cls.displayName.padding(toLength: 24, withPad: " ", startingAt: 0)) \(counts[cls]!)")
    }

case "near":
    guard args.count >= 2 else { fail("usage: near <system> [radius]") }
    let origin = resolve(args[1])
    let radius = args.count > 2 ? Double(args[2]) ?? 20 : 20
    for s in galaxy.systems(within: radius, of: origin.position) {
        let d = s.position.distance(to: origin.position)
        let flag = s.isCatalogued ? "real" : "    "
        print(String(format: "%7.2f ly  %@  %-8@ %@ %@  %@", d, flag, s.primarySpectralType,
                     s.starCount > 1 ? "×\(s.starCount)" : "  ", s.isPopulated ? "pop" : "   ", s.name))
    }

case "system":
    guard args.count >= 2 else { fail("usage: system <system>") }
    let s = resolve(args[1])
    let t0 = Date()
    let detail = galaxy.system(s.id)!
    printSystem(detail)
    print(String(format: "(generated in %.2f ms)", Date().timeIntervalSince(t0) * 1000))

case "route":
    guard args.count >= 4, let range = Double(args[3]) else { fail("usage: route <from> <to> <range>") }
    let a = resolve(args[1]), b = resolve(args[2])
    let t0 = Date()
    guard let path = galaxy.route(from: a.id, to: b.id, jumpRange: range) else { fail("No route found") }
    print("\(path.count - 1) jumps, direct distance \(ly(a.position.distance(to: b.position))):")
    var previous: SystemSummary?
    for s in path {
        let hop = previous.map { s.position.distance(to: $0.position) } ?? 0
        print(String(format: "  %6.2f ly  %@", hop, s.name))
        previous = s
    }
    print(String(format: "(plotted in %.2f s)", Date().timeIntervalSince(t0)))

case "map":
    guard args.count >= 2 else { fail("usage: map <out.ppm> [size] [extent]") }
    let size = args.count > 2 ? Int(args[2]) ?? 1024 : 1024
    let extent = args.count > 3 ? Double(args[3]) ?? 110_000 : 110_000
    let t0 = Date()
    let image = GalaxyMapRenderer.render(galaxy, size: size, extentLY: extent)
    try image.ppmData().write(to: URL(fileURLWithPath: args[1]))
    let sol = image.pixel(for: .sol)
    print(String(format: "Wrote %@ (%dx%d) in %.1fs. Sol is at pixel (%.1f, %.1f).", args[1], size, size,
                 Date().timeIntervalSince(t0), sol.x, sol.y))

case "export":
    guard args.count >= 2 else { fail("usage: export <out.json> [detail-radius] [summary-radius]") }
    let detailRadius = args.count > 2 ? Double(args[2]) ?? 25 : 25
    let summaryRadius = args.count > 3 ? Double(args[3]) ?? 60 : 60
    struct Export: Encodable {
        var seed: String
        var systems: [SystemSummary]
        var details: [StarSystem]
        var famous: [SystemSummary]
    }
    let summaries = galaxy.systems(within: summaryRadius, of: .sol)
    let details = summaries.filter { $0.distanceFromSol <= detailRadius || $0.isCatalogued }.compactMap { galaxy.system($0.id) }
    let famous = galaxy.catalogue
    let export = Export(seed: String(format: "%016llX", galaxy.seed), systems: summaries, details: details, famous: famous)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(export).write(to: URL(fileURLWithPath: args[1]))
    print("Wrote \(summaries.count) systems, \(details.count) with full detail, to \(args[1])")

default:
    fail("Unknown command \(command)")
}
