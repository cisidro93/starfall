import SwiftUI
import StarfallGalaxy

struct SolOverviewView: View {
    private let solSystem: StarSystem

    init() {
        let galaxy = Galaxy()
        self.solSystem = galaxy.system(galaxy.sol.id)!
    }

    private var primaryStarSummary: String {
        guard let star = solSystem.stars.first else { return "Unknown Star" }
        let tempText = String(format: "%.0f K", star.temperatureK)
        return "\(star.spectralType) • \(star.stellarClass.displayName) • \(tempText)"
    }

    private var settlementSummary: String {
        guard let settlement = solSystem.settlement else { return "Uninhabited" }
        let popBillions = Double(settlement.population) / 1_000_000_000.0
        let popText = String(format: "%.1fB", popBillions)
        return "Population: \(popText) • Economy: \(settlement.economy.rawValue) • Security: \(settlement.security.rawValue)"
    }

    private var stations: [Station] {
        solSystem.settlement?.stations ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section("System Overview") {
                    SystemHeaderRow(
                        name: solSystem.name,
                        systemID: solSystem.id.description,
                        starSummary: primaryStarSummary,
                        settlementSummary: settlementSummary
                    )
                }

                if !stations.isEmpty {
                    Section("Orbital & Surface Stations (\(stations.count))") {
                        ForEach(stations, id: \.name) { station in
                            StationRowView(station: station)
                        }
                    }
                }

                Section("Planets & Major Bodies (\(solSystem.bodies.count))") {
                    ForEach(solSystem.bodies, id: \.name) { body in
                        PlanetRowView(planet: body)
                    }
                }
            }
            .navigationTitle("STARFALL — \(solSystem.name.uppercased()) SYSTEM")
        }
    }
}

private struct SystemHeaderRow: View {
    let name: String
    let systemID: String
    let starSummary: String
    let settlementSummary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Spacer()
                Text(systemID)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(starSummary)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.orange)
            Text(settlementSummary)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct StationRowView: View {
    let station: Station

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(station.name)
                    .font(.system(size: 17, weight: .semibold))
                Text(station.type.rawValue)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Orbiting \(station.orbiting)")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.cyan)
        }
        .padding(.vertical, 2)
    }
}

private struct PlanetRowView: View {
    let planet: Body

    private var orbitAndSizeText: String {
        let auText = String(format: "%.3f AU", planet.semiMajorAxisAU)
        let radiusText = String(format: "%.0f km", planet.radiusKm)
        let gravityText = String(format: "%.2f g", planet.surfaceGravityG)
        let tempText = String(format: "%.0f K", planet.temperatureK)
        return "\(planet.kind.rawValue) • \(auText) • r=\(radiusText) • \(gravityText) • \(tempText)"
    }

    private var moonNamesText: String? {
        guard !planet.moons.isEmpty else { return nil }
        let names = planet.moons.map(\.name).joined(separator: ", ")
        return "Moons (\(planet.moons.count)): \(names)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(planet.name)
                    .font(.system(size: 18, weight: .semibold))
                if planet.isInHabitableZone {
                    Text("HABITABLE ZONE")
                        .font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }
                Spacer()
                Text(planet.landing.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(planet.landing == .notLandable ? .secondary : .mint)
            }
            Text(orbitAndSizeText)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            if let moons = moonNamesText {
                Text(moons)
                    .font(.system(size: 14))
                    .foregroundStyle(.teal)
            }
        }
        .padding(.vertical, 4)
    }
}
