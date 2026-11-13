import Foundation
import SwiftUI
import simd
import StarfallGalaxy

enum WaypointKind: String, Sendable, CaseIterable {
    case station = "STATION"
    case combatZone = "COMBAT ZONE"
    case beacon = "SALVAGE BEACON"
    case planet = "PLANET"
    case moon = "MOON"
    case star = "STAR"
    case jumpTarget = "HIGH-WAKE SYSTEM"

    var iconName: String {
        switch self {
        case .station: return "S"
        case .combatZone: return "▲"
        case .beacon: return "◇"
        case .planet: return "●"
        case .moon: return "◐"
        case .star: return "✦"
        case .jumpTarget: return "◈"
        }
    }

    var color: Color {
        switch self {
        case .station: return .cyan
        case .combatZone: return .red
        case .beacon: return .mint
        case .planet: return .orange
        case .moon: return Color(red: 0.78, green: 0.82, blue: 0.90)
        case .star: return .yellow
        case .jumpTarget: return .cyan
        }
    }
}

struct NavigationWaypoint: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let detailText: String
    let kind: WaypointKind
    /// Position in local Sol world frame (metres from player spawn origin).
    let worldPosition: SIMD3<Double>
    let radiusMetres: Double
    /// Sector grid coordinate (0...15, 0...15) for the Vendetta-style local sector grid.
    let sectorGridX: Int
    let sectorGridY: Int
    /// Optional target star system if this waypoint is an interstellar jump target.
    let targetSystem: SystemSummary?
    /// Whether the player can perform an in-system micro-jump directly to this local coordinate.
    let supportsLocalJump: Bool

    static func == (lhs: NavigationWaypoint, rhs: NavigationWaypoint) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// A 3D contact displayed on the Elite-style bottom-center holographic sensor disc.
struct SensorDiscContact: Identifiable, Sendable {
    let id: String
    let label: String
    /// Normalized position in ship-local radar space (-1...1 on X/Z disc plane, -1...1 on Y elevation stalk).
    let discX: Float
    let discZ: Float
    let elevationY: Float
    let isHostile: Bool
    let isLockedTarget: Bool
    let isStation: Bool
    let isWaypoint: Bool
}

@MainActor
final class NavigationWaypointManager: ObservableObject {
    @Published private(set) var localWaypoints: [NavigationWaypoint] = []
    @Published private(set) var systemBodyWaypoints: [NavigationWaypoint] = []
    @Published private(set) var nearbyStarWaypoints: [NavigationWaypoint] = []
    @Published var activeWaypoint: NavigationWaypoint
    @Published var plottedRoute: [SystemSummary] = []
    @Published var jumpRangeLY: Double = 12.0

    let galaxy = Galaxy()
    let solSystem: StarSystem

    init() {
        let g = Galaxy()
        let sol = g.system(g.sol.id)!
        self.solSystem = sol

        let earthBody = sol.bodies.first { $0.name == "Earth" }!
        let moonBody = earthBody.moons.first { $0.name == "Moon" }!
        let earthRadiusM = earthBody.radiusKm * 1_000.0
        let earthDir = simd_normalize(SIMD3<Double>(-0.48, -0.16, -0.86))
        let earthWorldPos = earthDir * (earthRadiusM + 9_100_000.0)
        let moonDir = simd_normalize(SIMD3<Double>(0.52, 0.22, -0.82))
        let moonWorldPos = earthWorldPos + moonDir * (moonBody.semiMajorAxisKm * 1_000.0)
        let sunDir = simd_normalize(SIMD3<Double>(0.74, 0.32, -0.59))
        let sunWorldPos = sunDir * (earthBody.semiMajorAxisKm * 1_000.0)

        let gagarinPos = SIMD3<Double>(0.0, 0.0, -900.0)
        let patrolAlphaPos = SIMD3<Double>(-520.0, 90.0, -680.0)
        let derelictPos = SIMD3<Double>(480.0, -75.0, -560.0)
        let navBeaconPos = SIMD3<Double>(140.0, 110.0, -320.0)

        let gagarinWP = NavigationWaypoint(
            id: "wp_gagarin_gateway",
            name: "Gagarin Gateway",
            subtitle: "Ring Station • Orbiting Earth",
            detailText: "Primary orbital habitat & docking hub in high Earth orbit. Clear 450m mass-lock perimeter before engaging jump drive.",
            kind: .station,
            worldPosition: gagarinPos,
            radiusMetres: 165.0,
            sectorGridX: 8,
            sectorGridY: 5,
            targetSystem: nil,
            supportsLocalJump: true
        )

        let patrolWP = NavigationWaypoint(
            id: "wp_patrol_alpha",
            name: "Patrol Sector Alpha",
            subtitle: "Combat Zone • 3 Hostile Drones",
            detailText: "Active weapons-testing perimeter patrolled by 3 autonomous SF-D aggressor drones.",
            kind: .combatZone,
            worldPosition: patrolAlphaPos,
            radiusMetres: 120.0,
            sectorGridX: 5,
            sectorGridY: 6,
            targetSystem: nil,
            supportsLocalJump: true
        )

        let derelictWP = NavigationWaypoint(
            id: "wp_derelict_hulk",
            name: "Forsaken Relay Hulk",
            subtitle: "Salvage Wreckage • High-Orbit Debris",
            detailText: "Shattered deep-space relay superstructure surrounded by floating hull plating. Ideal for 6DOF Flight Assist OFF weaving.",
            kind: .beacon,
            worldPosition: derelictPos,
            radiusMetres: 60.0,
            sectorGridX: 11,
            sectorGridY: 6,
            targetSystem: nil,
            supportsLocalJump: true
        )

        let navBeaconWP = NavigationWaypoint(
            id: "wp_sol_nav_beacon",
            name: "Earth Orbital Nav Beacon",
            subtitle: "Telemetry Transponder • Sector E8",
            detailText: "High-gain system navigation transponder broadcasting Sol orbital ephemeris and docking approach corridors.",
            kind: .beacon,
            worldPosition: navBeaconPos,
            radiusMetres: 15.0,
            sectorGridX: 9,
            sectorGridY: 7,
            targetSystem: nil,
            supportsLocalJump: true
        )

        self.localWaypoints = [gagarinWP, patrolWP, derelictWP, navBeaconWP]
        self.activeWaypoint = gagarinWP

        // Build Sol System Bodies & Stations
        var sysWPs: [NavigationWaypoint] = []
        if let star = sol.stars.first {
            sysWPs.append(
                NavigationWaypoint(
                    id: "wp_star_sol",
                    name: "Sol (\(star.spectralType))",
                    subtitle: "G-Type Main Sequence Star • 1.000 AU",
                    detailText: String(format: "Surface Temp: %.0f K • Mass: %.2f M☉ • Luminosity: %.2f L☉", star.temperatureK, star.massSolar, star.luminositySolar),
                    kind: .star,
                    worldPosition: sunWorldPos,
                    radiusMetres: star.radiusSolar * 696_340_000.0,
                    sectorGridX: 14,
                    sectorGridY: 2,
                    targetSystem: nil,
                    supportsLocalJump: false
                )
            )
        }

        let stations = sol.settlement?.stations ?? []
        for (idx, body) in sol.bodies.enumerated() {
            let bodyPos: SIMD3<Double>
            if body.name == "Earth" {
                bodyPos = earthWorldPos
            } else {
                let angle = Double(idx) * 1.15 + 0.4
                let distM = body.semiMajorAxisAU * 149_597_870_700.0
                let dir = simd_normalize(SIMD3<Double>(cos(angle), sin(angle * 0.5) * 0.15, -sin(angle)))
                bodyPos = sunWorldPos + dir * distM
            }

            let auStr = String(format: "%.2f AU", body.semiMajorAxisAU)
            let gravStr = String(format: "%.2f g", body.surfaceGravityG)
            let tempStr = String(format: "%.0f K", body.temperatureK)
            let orbitingStations = stations.filter { $0.orbiting == body.name }.map(\.name)
            let stnNote = orbitingStations.isEmpty ? "" : " • Stations: \(orbitingStations.joined(separator: ", "))"

            sysWPs.append(
                NavigationWaypoint(
                    id: "wp_body_\(body.name.lowercased())",
                    name: body.name,
                    subtitle: "\(body.kind.rawValue) • \(auStr)\(stnNote)",
                    detailText: "Radius: \(Int(body.radiusKm)) km • Gravity: \(gravStr) • Temp: \(tempStr) • \(body.landing.rawValue)",
                    kind: .planet,
                    worldPosition: bodyPos,
                    radiusMetres: body.radiusKm * 1_000.0,
                    sectorGridX: min(15, max(0, 2 + idx * 2)),
                    sectorGridY: body.name == "Earth" ? 3 : 1,
                    targetSystem: nil,
                    supportsLocalJump: false
                )
            )

            if body.name == "Earth" {
                sysWPs.append(
                    NavigationWaypoint(
                        id: "wp_moon_luna",
                        name: "Moon (Luna)",
                        subtitle: "Rocky Moon • Orbiting Earth • 384,400 km",
                        detailText: "Radius: 1,737 km • Gravity: 0.17 g • Surface Port: Armstrong Landing",
                        kind: .moon,
                        worldPosition: moonWorldPos,
                        radiusMetres: moonBody.radiusKm * 1_000.0,
                        sectorGridX: 12,
                        sectorGridY: 3,
                        targetSystem: nil,
                        supportsLocalJump: false
                    )
                )
            }
        }
        self.systemBodyWaypoints = sysWPs

        // Nearby Catalogued Star Systems within 18 LY from StarfallGalaxy
        let neighbours = g.systems(within: 18.0, of: .sol, limit: 24).filter { $0.id != g.sol.id }
        var starWPs: [NavigationWaypoint] = []
        for sys in neighbours {
            // Convert GalacticPosition (in LY relative to Sol) into a distant directional world coordinate
            let posVec = SIMD3<Double>(sys.position.x, sys.position.y, sys.position.z)
            let distLY = max(0.1, simd_length(posVec))
            let dir = posVec / distLY
            let metresPerLY = 9.4607e15
            let worldPos = dir * (distLY * metresPerLY)
            let dText = String(format: "%.2f LY", distLY)
            let popText = sys.isPopulated ? "Populated System" : "Uninhabited Frontier"

            starWPs.append(
                NavigationWaypoint(
                    id: "wp_sys_\(sys.id.description)",
                    name: sys.name,
                    subtitle: "\(sys.primarySpectralType) • \(dText) from Sol",
                    detailText: "\(sys.primaryClass.displayName) • \(sys.starCount) Star(s) • \(popText)",
                    kind: .jumpTarget,
                    worldPosition: worldPos,
                    radiusMetres: 696_340_000.0,
                    sectorGridX: 8,
                    sectorGridY: 0,
                    targetSystem: sys,
                    supportsLocalJump: false
                )
            )
        }
        self.nearbyStarWaypoints = starWPs
    }

    var allWaypoints: [NavigationWaypoint] {
        localWaypoints + systemBodyWaypoints + nearbyStarWaypoints
    }

    func selectWaypoint(_ waypoint: NavigationWaypoint) {
        activeWaypoint = waypoint
        if let targetSys = waypoint.targetSystem {
            plottedRoute = galaxy.route(from: galaxy.sol.id, to: targetSys.id, jumpRange: jumpRangeLY) ?? [galaxy.sol, targetSys]
        } else {
            plottedRoute = []
        }
    }

    func cycleNextLocalWaypoint() {
        let pool = localWaypoints + systemBodyWaypoints.prefix(3)
        guard !pool.isEmpty else { return }
        if let idx = pool.firstIndex(where: { $0.id == activeWaypoint.id }) {
            let nextIdx = (idx + 1) % pool.count
            selectWaypoint(pool[nextIdx])
        } else {
            selectWaypoint(pool[0])
        }
    }

    static func formatDistance(_ metres: Double) -> String {
        let lyMetres = 9.4607e15
        let auMetres = 149_597_870_700.0
        if metres >= lyMetres * 0.1 {
            return String(format: "%.2f LY", metres / lyMetres)
        } else if metres >= auMetres * 0.05 {
            return String(format: "%.2f AU", metres / auMetres)
        } else if metres >= 1_000_000.0 {
            return String(format: "%.0f km", metres / 1_000.0)
        } else if metres >= 1_000.0 {
            return String(format: "%.2f km", metres / 1_000.0)
        } else {
            return String(format: "%.0f m", metres)
        }
    }
}
