import Foundation
import XCTest
@testable import StarfallGalaxy

final class GalaxyTests: XCTestCase {
    let galaxy = Galaxy()

    // MARK: Determinism

    func testSameSeedSameGalaxy() throws {
        let other = Galaxy()
        let centre = GalacticPosition(x: 120, y: 5, z: -80)
        let a = galaxy.systems(within: 25, of: centre)
        let b = other.systems(within: 25, of: centre)
        XCTAssertFalse(a.isEmpty)
        XCTAssertEqual(a, b)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for s in a.prefix(20) {
            let da = try encoder.encode(galaxy.system(s.id)!)
            let db = try encoder.encode(other.system(s.id)!)
            XCTAssertEqual(da, db, "\(s.name) differs between two generations")
        }
    }

    func testDifferentSeedsDiffer() {
        let other = Galaxy(seed: 42)
        let centre = GalacticPosition(x: 120, y: 5, z: -80)
        XCTAssertNotEqual(galaxy.systems(within: 25, of: centre).map(\.position),
                          other.systems(within: 25, of: centre).map(\.position))
    }

    func testSummaryAgreesWithDetail() {
        for s in galaxy.systems(within: 30, of: GalacticPosition(x: -60, y: 0, z: 40)).prefix(200) where !s.isCatalogued {
            let detail = galaxy.system(s.id)!
            XCTAssertEqual(detail.stars.count, s.starCount, s.name)
            XCTAssertEqual(detail.stars[0].stellarClass, s.primaryClass, s.name)
            XCTAssertEqual(detail.settlement != nil, s.isPopulated, s.name)
        }
    }

    func testIDRoundTrip() {
        for s in galaxy.systems(within: 20, of: GalacticPosition(x: 300, y: -20, z: 300)).prefix(50) {
            let again = galaxy.summary(for: s.id)
            XCTAssertEqual(again, s)
            XCTAssertEqual(SystemID(string: s.id.description), s.id)
        }
    }

    // MARK: Real sky

    func testSolIsHome() {
        let sol = galaxy.sol
        XCTAssertEqual(sol.position, .sol)
        let detail = galaxy.system(sol.id)!
        XCTAssertEqual(detail.bodies.map(\.name).prefix(4), ["Mercury", "Venus", "Earth", "Mars"])
        XCTAssertEqual(detail.settlement?.isCapital, true)
        XCTAssertEqual(detail.bodies.first { $0.name == "Earth" }?.moons.first?.name, "Moon")
    }

    func testNearestStarDistances() {
        XCTAssertEqual(galaxy.system(named: "Alpha Centauri")!.distanceFromSol, 4.37, accuracy: 0.01)
        XCTAssertEqual(galaxy.system(named: "Sirius")!.distanceFromSol, 8.60, accuracy: 0.01)
        XCTAssertEqual(galaxy.system(named: "tau ceti")!.distanceFromSol, 11.91, accuracy: 0.01)
    }

    /// Checks the equatorial-to-galactic conversion against published galactic coordinates.
    func testRealStarsPointTheRightWay() {
        func expected(l: Double, b: Double, d: Double) -> GalacticPosition {
            let lr = l * .pi / 180, br = b * .pi / 180
            return GalacticPosition(x: d * cos(br) * sin(lr), y: d * sin(br), z: d * cos(br) * cos(lr))
        }
        // Sirius: l = 227.23°, b = -8.89°. Vega: l = 67.45°, b = 19.24°. Betelgeuse: l = 199.79°, b = -8.96°.
        let checks: [(String, GalacticPosition, Double)] = [
            ("Sirius", expected(l: 227.23, b: -8.89, d: 8.60), 0.05),
            ("Vega", expected(l: 67.45, b: 19.24, d: 25.04), 0.15),
            ("Betelgeuse", expected(l: 199.79, b: -8.96, d: 548), 3.0),
        ]
        for (name, want, tolerance) in checks {
            let got = galaxy.system(named: name)!.position
            XCTAssertLessThan(got.distance(to: want), tolerance, "\(name) is at \(got), expected \(want)")
        }
    }

    func testCatalogueBubbleHasNoFakeStars() {
        let near = galaxy.systems(within: StarCatalogue.completeRadiusLY - 0.1, of: .sol)
        XCTAssertTrue(near.allSatisfy(\.isCatalogued))
        XCTAssertGreaterThan(near.count, 20)
    }

    func testKnownExoplanetsArePlacedExactly() {
        let proxima = galaxy.system(galaxy.system(named: "Alpha Centauri")!.id)!
        let b = proxima.bodies.first { $0.name == "Proxima Centauri b" }
        XCTAssertNotNil(b)
        XCTAssertEqual(b!.semiMajorAxisAU, 0.0485, accuracy: 0.0001)
        XCTAssertTrue(b!.isCatalogued)
        XCTAssertTrue(b!.isInHabitableZone)
    }

    // MARK: Galaxy shape

    func testLocalDensityMatchesTheSolarNeighbourhood() {
        // Roughly 1,700 systems are expected within 50 ly; allow for clumpiness.
        let count = galaxy.systems(within: 50, of: .sol).count
        XCTAssertGreaterThan(count, 1_200)
        XCTAssertLessThan(count, 2_400)
    }

    func testCoreIsDenseAndEdgeIsSparse() {
        let d = galaxy.density
        let sol = d.systemsPerCubicLY(at: .sol)
        let nearCore = d.systemsPerCubicLY(at: GalacticPosition(x: 0, y: -21, z: 24_000))
        let edge = d.systemsPerCubicLY(at: GalacticPosition(x: 0, y: 0, z: -40_000))
        let aboveDisk = d.systemsPerCubicLY(at: GalacticPosition(x: 0, y: 6_000, z: 0))
        XCTAssertGreaterThan(nearCore, sol * 10)
        XCTAssertLessThan(edge, sol / 20)
        // About 2 kpc above the plane, thick disk plus halo give roughly 1-3% of the local density.
        XCTAssertLessThan(aboveDisk, sol / 25)
    }

    // MARK: Human space

    func testHumanSpaceThinsWithDistance() {
        func populatedShare(at p: GalacticPosition) -> Double {
            let s = galaxy.systems(within: 15, of: p)
            return Double(s.filter(\.isPopulated).count) / Double(max(1, s.count))
        }
        let near = populatedShare(at: GalacticPosition(x: 25, y: 0, z: 10))
        let far = populatedShare(at: GalacticPosition(x: 250, y: 0, z: 0))
        XCTAssertGreaterThan(near, 0.3)
        XCTAssertLessThan(far, 0.1)
        XCTAssertTrue(galaxy.systems(within: 10, of: GalacticPosition(x: 0, y: 0, z: 800)).allSatisfy { !$0.isPopulated })
    }

    // MARK: Routes

    func testRouteRespectsJumpRange() {
        let sol = galaxy.sol, tauCeti = galaxy.system(named: "Tau Ceti")!
        let path = galaxy.route(from: sol.id, to: tauCeti.id, jumpRange: 10)
        XCTAssertNotNil(path)
        XCTAssertEqual(path?.first?.id, sol.id)
        XCTAssertEqual(path?.last?.id, tauCeti.id)
        XCTAssertGreaterThanOrEqual(path!.count, 3)
        for (a, b) in zip(path!, path!.dropFirst()) {
            XCTAssertLessThanOrEqual(a.position.distance(to: b.position), 10.0001)
        }
    }

    // MARK: Map

    func testMapRendersWithSolInFrame() {
        let image = GalaxyMapRenderer.render(galaxy, size: 64, verticalSamples: 6)
        XCTAssertEqual(image.pixels.count, 64 * 64 * 3)
        let sol = image.pixel(for: .sol)
        XCTAssertTrue((0..<64).contains(Int(sol.x)) && (0..<64).contains(Int(sol.y)))
        // The core is brighter than the outskirts.
        let core = image.pixel(for: .galacticCentre)
        func brightness(_ x: Int, _ y: Int) -> Int {
            let i = (y * 64 + x) * 3
            return Int(image.pixels[i]) + Int(image.pixels[i + 1]) + Int(image.pixels[i + 2])
        }
        XCTAssertGreaterThan(brightness(Int(core.x), Int(core.y)), brightness(2, 2))
    }
}
