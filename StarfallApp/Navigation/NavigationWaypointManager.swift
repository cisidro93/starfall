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
    let worldPosition: SIMD3<Double>
    let radiusMetres: Double
    let sectorGridX: Int
    let sectorGridY: Int
    let targetSystem: SystemSummary?
    let supportsLocalJump: Bool

    static func == (lhs: NavigationWaypoint, rhs: NavigationWaypoint) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct SensorDiscContact: Identifiable, Sendable {
    let id: String
    let label: String
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
    @Published private(set) var currentSystem: StarSystem
    @Published private(set) var localWaypoints: [NavigationWaypoint] = []
    @Published private(set) var systemBodyWaypoints: [NavigationWaypoint] = []
    @Published private(set) var nearbyStarWaypoints: [NavigationWaypoint] = []
    @Published var activeWaypoint: NavigationWaypoint
    @Published var plottedRoute: [SystemSummary] = []
    @Published var jumpRangeLY: Double = 12.0

    let galaxy = Galaxy()

    init() {
        let g = Galaxy()
        let sol = g.system(g.sol.id)!
        self.currentSystem = sol
        let dummyWP = NavigationWaypoint(
            id: "wp_init",
            name: "Gagarin Gateway",
            subtitle: "Ring Station",
            detailText: "",
            kind: .station,
            worldPosition: SIMD3<Double>(0, 0, -900),
            radiusMetres: 165,
            sectorGridX: 8,
            sectorGridY: 5,
            targetSystem: nil,
            supportsLocalJump: true
        )
        self.activeWaypoint = dummyWP
        loadSystem(systemID: sol.id)
    }

    var primaryStationName: String {
        currentSystem.settlement?.stations.first?.name ?? "\(currentSystem.name) Orbital"
    }

    var primaryEconomy: Economy {
        currentSystem.settlement?.economy ?? .colony
    }

    var primarySecurityText: String {
        currentSystem.settlement?.security.rawValue ?? "Uninhabited"
    }

    func loadSystem(systemID: SystemID) {
        let sys = galaxy.system(systemID) ?? galaxy.system(galaxy.sol.id)!
        self.currentSystem = sys

        let primaryStar = sys.stars.first!
        let primaryPlanet = sys.bodies.first(where: { $0.name == "Earth" }) ?? sys.bodies.first
        let primaryRadiusM = (primaryPlanet?.radiusKm ?? 6_371.0) * 1_000.0
        let planetDir = simd_normalize(SIMD3<Double>(-0.48, -0.16, -0.86))
        let planetWorldPos = planetDir * (primaryRadiusM + 9_100_000.0)
        let moonDir = simd_normalize(SIMD3<Double>(0.52, 0.22, -0.82))
        let moonWorldPos = planetWorldPos + moonDir * 384_400_000.0
        let sunDir = simd_normalize(SIMD3<Double>(0.74, 0.32, -0.59))
        let sunWorldPos = sunDir * 149_597_870_700.0

        let stnName = sys.settlement?.stations.first?.name ?? "\(sys.name) Gateway"
        let anchorName = primaryPlanet?.name ?? sys.name

        let gagarinPos = SIMD3<Double>(0.0, 0.0, -900.0)
        let patrolAlphaPos = SIMD3<Double>(-220.0, 45.0, -480.0)
        let derelictPos = SIMD3<Double>(480.0, -75.0, -560.0)
        let navBeaconPos = SIMD3<Double>(140.0, 110.0, -320.0)

        let stnWP = NavigationWaypoint(
            id: "wp_primary_station",
            name: stnName,
            subtitle: "Ring Station • Orbiting \(anchorName)",
            detailText: "Primary orbital Coriolis/Ring port in \(sys.name). Request docking clearance within 7.5 km to land on Pad 04 and access Starport Services.",
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
            name: "Resource Extraction / Patrol Zone",
            subtitle: "Combat Zone • Wanted Pirate Drones (+12,500 CR)",
            detailText: "Active pirate interception zone. Destroy wanted aggressor drones to earn 12,500 CR bounty vouchers redeemable at \(stnName).",
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
            detailText: "Shattered deep-space relay superstructure surrounded by floating hull plating.",
            kind: .beacon,
            worldPosition: derelictPos,
            radiusMetres: 60.0,
            sectorGridX: 11,
            sectorGridY: 6,
            targetSystem: nil,
            supportsLocalJump: true
        )

        let navBeaconWP = NavigationWaypoint(
            id: "wp_nav_beacon",
            name: "\(sys.name) Nav Beacon",
            subtitle: "System Telemetry Transponder • Sector E8",
            detailText: "High-gain system navigation transponder broadcasting \(sys.name) orbital ephemeris and trade lane data.",
            kind: .beacon,
            worldPosition: navBeaconPos,
            radiusMetres: 15.0,
            sectorGridX: 9,
            sectorGridY: 7,
            targetSystem: nil,
            supportsLocalJump: true
        )

        self.localWaypoints = [stnWP, patrolWP, derelictWP, navBeaconWP]
        self.activeWaypoint = stnWP

        // Build System Bodies & Stations
        var sysWPs: [NavigationWaypoint] = []
        sysWPs.append(
            NavigationWaypoint(
                id: "wp_star_primary",
                name: "\(primaryStar.name) (\(primaryStar.spectralType))",
                subtitle: "\(primaryStar.stellarClass.displayName) • Primary Star",
                detailText: String(format: "Surface Temp: %.0f K • Mass: %.2f M☉ • Luminosity: %.2f L☉", primaryStar.temperatureK, primaryStar.massSolar, primaryStar.luminositySolar),
                kind: .star,
                worldPosition: sunWorldPos,
                radiusMetres: max(0.15, primaryStar.radiusSolar) * 696_340_000.0,
                sectorGridX: 14,
                sectorGridY: 2,
                targetSystem: nil,
                supportsLocalJump: false
            )
        )

        let stations = sys.settlement?.stations ?? []
        for (idx, body) in sys.bodies.enumerated() {
            let bodyPos: SIMD3<Double>
            if idx == 0 || body.name == "Earth" {
                bodyPos = planetWorldPos
            } else {
                let angle = Double(idx) * 1.15 + 0.4
                let distM = max(0.2, body.semiMajorAxisAU) * 149_597_870_700.0
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
                    id: "wp_body_\(idx)_\(body.name.lowercased())",
                    name: body.name,
                    subtitle: "\(body.kind.rawValue) • \(auStr)\(stnNote)",
                    detailText: "Radius: \(Int(body.radiusKm)) km • Gravity: \(gravStr) • Temp: \(tempStr) • \(body.landing.rawValue)",
                    kind: .planet,
                    worldPosition: bodyPos,
                    radiusMetres: max(500.0, body.radiusKm) * 1_000.0,
                    sectorGridX: min(15, max(0, 2 + idx * 2)),
                    sectorGridY: idx == 0 ? 3 : 1,
                    targetSystem: nil,
                    supportsLocalJump: true
                )
            )

            if let firstMoon = body.moons.first {
                sysWPs.append(
                    NavigationWaypoint(
                        id: "wp_moon_\(idx)_\(firstMoon.name.lowercased())",
                        name: firstMoon.name,
                        subtitle: "\(firstMoon.kind.rawValue) Moon • Orbiting \(body.name)",
                        detailText: "Radius: \(Int(firstMoon.radiusKm)) km • Gravity: \(String(format: "%.2f g", firstMoon.surfaceGravityG))",
                        kind: .moon,
                        worldPosition: moonWorldPos,
                        radiusMetres: max(200.0, firstMoon.radiusKm) * 1_000.0,
                        sectorGridX: 12,
                        sectorGridY: 3,
                        targetSystem: nil,
                        supportsLocalJump: true
                    )
                )
            }
        }
        self.systemBodyWaypoints = sysWPs

        // Nearby Star Systems within 20 LY of the current system
        let centrePos = sys.summary.position
        let neighbours = galaxy.systems(within: 20.0, of: centrePos, limit: 26).filter { $0.id != sys.id }
        var starWPs: [NavigationWaypoint] = []
        for nSys in neighbours {
            let rel = SIMD3<Double>(
                nSys.position.x - centrePos.x,
                nSys.position.y - centrePos.y,
                nSys.position.z - centrePos.z
            )
            let distLY = max(0.1, simd_length(rel))
            let dir = rel / distLY
            let metresPerLY = 9.4607e15
            let worldPos = dir * (distLY * metresPerLY)
            let dText = String(format: "%.2f LY", distLY)
            let popText = nSys.isPopulated ? "Populated System" : "Uninhabited Frontier"

            starWPs.append(
                NavigationWaypoint(
                    id: "wp_sys_\(nSys.id.description)",
                    name: nSys.name,
                    subtitle: "\(nSys.primarySpectralType) • \(dText) from \(sys.name)",
                    detailText: "\(nSys.primaryClass.displayName) • \(nSys.starCount) Star(s) • \(popText)",
                    kind: .jumpTarget,
                    worldPosition: worldPos,
                    radiusMetres: 696_340_000.0,
                    sectorGridX: 8,
                    sectorGridY: 0,
                    targetSystem: nSys,
                    supportsLocalJump: false
                )
            )
        }
        self.nearbyStarWaypoints = starWPs
        self.plottedRoute = []
    }

    var allWaypoints: [NavigationWaypoint] {
        localWaypoints + systemBodyWaypoints + nearbyStarWaypoints
    }

    func selectWaypoint(_ waypoint: NavigationWaypoint) {
        activeWaypoint = waypoint
        if let targetSys = waypoint.targetSystem {
            plottedRoute = galaxy.route(from: currentSystem.id, to: targetSys.id, jumpRange: jumpRangeLY) ?? [currentSystem.summary, targetSys]
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
        if metres >= lyMetres * 0.05 {
            return String(format: "%.2f LY", metres / lyMetres)
        } else if metres >= auMetres * 0.01 {
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
