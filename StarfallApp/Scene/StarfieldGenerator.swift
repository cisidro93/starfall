import Foundation
import RealityKit
import UIKit
import simd
import StarfallGalaxy

@MainActor
enum StarfieldGenerator {

    private struct StarQuad {
        var direction: SIMD3<Float>
        var angularSize: Float
    }

    /// Creates the procedural starfield skybox entity centred on the origin.
    /// Combines real catalogued stars from `StarfallGalaxy` with deterministic procedural
    /// field and Milky Way band stars, batched by spectral colour into 5 meshes.
    static func makeSkyboxEntity(seed: UInt64 = Galaxy.defaultSeed) -> Entity {
        let root = Entity()
        root.name = "StarfieldSkybox"

        // 1. Deep-space backdrop shell so the background is pure obsidian space black.
        if let backdrop = makeBackdropSphere(radius: 600.0) {
            root.addChild(backdrop)
        }

        // 2. Bucket stars by spectral colour so the entire skybox renders in 5 draw calls.
        var blueWhiteStars: [StarQuad] = []
        var whiteStars: [StarQuad] = []
        var yellowStars: [StarQuad] = []
        var orangeRedStars: [StarQuad] = []
        var milkyWayFaintStars: [StarQuad] = []

        // Place real catalogued stars from StarfallGalaxy in their true sky directions from Sol.
        let galaxy = Galaxy(seed: seed)
        for summary in galaxy.catalogue where summary.id != galaxy.sol.id {
            let pos = summary.position
            let raw = SIMD3<Float>(Float(pos.x), Float(pos.y), Float(pos.z))
            let len = simd_length(raw)
            guard len > 0.001 else { continue }
            let dir = raw / len

            // Closer / brighter catalogue landmarks get a slightly larger billboard angular size.
            let size: Float = summary.distanceFromSol < 30.0 ? 0.0042 : 0.0034
            let quad = StarQuad(direction: dir, angularSize: size)

            switch summary.primaryClass {
            case .O, .B:
                blueWhiteStars.append(quad)
            case .A, .whiteDwarf:
                whiteStars.append(quad)
            case .F, .G:
                yellowStars.append(quad)
            default:
                orangeRedStars.append(quad)
            }
        }

        // Deterministic procedural background starfield + Milky Way galactic plane band.
        var rng = SplitMix64(seed: seed ^ 0x57A2_F1E1_D001)

        // All-sky field stars (1,200 stars uniformly distributed on the sphere).
        for _ in 0..<1_200 {
            let z = Float(rng.uniform(-1.0, 1.0))
            let phi = Float(rng.uniform(0.0, 2.0 * .pi))
            let rXY = sqrt(max(0.0, 1.0 - z * z))
            let dir = SIMD3<Float>(rXY * cos(phi), z, rXY * sin(phi))
            let size = Float(rng.uniform(0.0014, 0.0028))
            let quad = StarQuad(direction: dir, angularSize: size)

            let roll = rng.unit()
            if roll < 0.12 {
                blueWhiteStars.append(quad)
            } else if roll < 0.38 {
                whiteStars.append(quad)
            } else if roll < 0.72 {
                yellowStars.append(quad)
            } else {
                orangeRedStars.append(quad)
            }
        }

        // Milky Way galactic plane band (1,400 faint stars concentrated near y = 0, denser toward +z Galactic Centre).
        for _ in 0..<1_400 {
            // Bias azimuth toward +z (angle = pi/2 in x-z plane).
            let towardsCore = rng.chance(0.55)
            let azimuth: Float
            if towardsCore {
                azimuth = Float.pi * 0.5 + Float(rng.uniform(-1.1, 1.1))
            } else {
                azimuth = Float(rng.uniform(0.0, 2.0 * .pi))
            }
            // Sum of two uniforms gives a triangular concentration around the galactic equator (y = 0).
            let latSpread = Float(rng.uniform(-0.22, 0.22) + rng.uniform(-0.22, 0.22))
            let raw = SIMD3<Float>(cos(azimuth), latSpread, sin(azimuth))
            let dir = simd_normalize(raw)
            let size = Float(rng.uniform(0.0010, 0.0020))
            milkyWayFaintStars.append(StarQuad(direction: dir, angularSize: size))
        }

        let tiers: [(String, [StarQuad], UIColor)] = [
            ("Stars_BlueWhite", blueWhiteStars, UIColor(red: 0.72, green: 0.86, blue: 1.00, alpha: 1.0)),
            ("Stars_White", whiteStars, UIColor(red: 0.96, green: 0.97, blue: 1.00, alpha: 1.0)),
            ("Stars_Yellow", yellowStars, UIColor(red: 1.00, green: 0.93, blue: 0.78, alpha: 1.0)),
            ("Stars_OrangeRed", orangeRedStars, UIColor(red: 1.00, green: 0.74, blue: 0.54, alpha: 1.0)),
            ("Stars_MilkyWayBand", milkyWayFaintStars, UIColor(red: 0.58, green: 0.66, blue: 0.84, alpha: 1.0)),
        ]

        for (name, stars, color) in tiers {
            if let tierEntity = makeStarBatchEntity(name: name, stars: stars, radius: 480.0, color: color) {
                root.addChild(tierEntity)
            }
        }

        return root
    }

    private static func makeStarBatchEntity(
        name: String,
        stars: [StarQuad],
        radius: Float,
        color: UIColor
    ) -> ModelEntity? {
        guard !stars.isEmpty else { return nil }

        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(stars.count * 4)
        indices.reserveCapacity(stars.count * 12)

        for star in stars {
            let dir = star.direction
            let refUp: SIMD3<Float> = abs(dir.y) > 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
            let right = simd_normalize(simd_cross(refUp, dir))
            let up = simd_cross(dir, right)

            let center = dir * radius
            let half = radius * star.angularSize

            let base = UInt32(positions.count)
            positions.append(center + up * half)
            positions.append(center + right * half)
            positions.append(center - up * half)
            positions.append(center - right * half)

            // Double-sided diamond quad so winding order never culls a star.
            indices.append(contentsOf: [
                base + 0, base + 1, base + 2,
                base + 0, base + 2, base + 3,
                base + 0, base + 2, base + 1,
                base + 0, base + 3, base + 2,
            ])
        }

        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)

        guard let mesh = try? MeshResource.generate(from: [descriptor]) else {
            return nil
        }

        let material = UnlitMaterial(color: color)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = name
        return entity
    }

    private static func makeBackdropSphere(radius: Float) -> ModelEntity? {
        let stacks = 16
        let slices = 32
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for i in 0...stacks {
            let v = Float(i) / Float(stacks)
            let phi = v * .pi
            let y = cos(phi) * radius
            let rSlice = sin(phi) * radius

            for j in 0...slices {
                let u = Float(j) / Float(slices)
                let theta = u * 2.0 * .pi
                let x = rSlice * cos(theta)
                let z = rSlice * sin(theta)
                positions.append(SIMD3<Float>(x, y, z))
            }
        }

        let stride = UInt32(slices + 1)
        for i in 0..<UInt32(stacks) {
            for j in 0..<UInt32(slices) {
                let row1 = i * stride + j
                let row2 = (i + 1) * stride + j
                // Both windings so inside of the sphere is always opaque.
                indices.append(contentsOf: [
                    row1, row2, row1 + 1,
                    row1 + 1, row2, row2 + 1,
                    row1, row1 + 1, row2,
                    row1 + 1, row2 + 1, row2,
                ])
            }
        }

        var descriptor = MeshDescriptor(name: "DeepSpaceBackdrop")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)

        guard let mesh = try? MeshResource.generate(from: [descriptor]) else {
            return nil
        }

        let spaceBlack = UIColor(red: 0.008, green: 0.010, blue: 0.020, alpha: 1.0)
        let material = UnlitMaterial(color: spaceBlack)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "DeepSpaceBackdrop"
        return entity
    }
}
