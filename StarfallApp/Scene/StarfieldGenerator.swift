import Foundation
import RealityKit
import UIKit
import CoreGraphics
import simd
import StarfallGalaxy

@MainActor
enum StarfieldGenerator {

    private struct StarQuad {
        var direction: SIMD3<Float>
        var angularSize: Float
    }

    /// Creates the procedural starfield skybox entity centred on the origin.
    /// Uses soft radial-glow and diffraction-spike sprite textures with UV mapping and
    /// alpha blending so stars render as crisp glowing points rather than blocky polygons.
    static func makeSkyboxEntity(seed: UInt64 = Galaxy.defaultSeed) -> Entity {
        let root = Entity()
        root.name = "StarfieldSkybox"

        if let backdrop = makeBackdropSphere(radius: 600.0) {
            root.addChild(backdrop)
        }

        let softTexture = makeStarTexture(size: 64, withSpikes: false)
        let landmarkTexture = makeStarTexture(size: 64, withSpikes: true)

        var landmarkBlueWhite: [StarQuad] = []
        var landmarkWarm: [StarQuad] = []

        var brightBlueWhite: [StarQuad] = []
        var brightWhite: [StarQuad] = []
        var brightYellow: [StarQuad] = []
        var brightOrangeRed: [StarQuad] = []

        var dimFieldStars: [StarQuad] = []
        var milkyWayBandStars: [StarQuad] = []

        // 1. Real catalogued stars from StarfallGalaxy in their true sky directions from Sol.
        let galaxy = Galaxy(seed: seed)
        for summary in galaxy.catalogue where summary.id != galaxy.sol.id {
            let pos = summary.position
            let raw = SIMD3<Float>(Float(pos.x), Float(pos.y), Float(pos.z))
            let len = simd_length(raw)
            guard len > 0.001 else { continue }
            let dir = raw / len

            let isBrightLandmark = summary.distanceFromSol < 45.0 || summary.primaryClass == .O || summary.primaryClass == .B || summary.name == "Betelgeuse" || summary.name == "Antares" || summary.name == "Rigel" || summary.name == "Deneb" || summary.name == "Canopus"
            let size: Float = isBrightLandmark ? 0.0085 : 0.0052
            let quad = StarQuad(direction: dir, angularSize: size)

            if isBrightLandmark {
                switch summary.primaryClass {
                case .O, .B, .A, .whiteDwarf:
                    landmarkBlueWhite.append(quad)
                default:
                    landmarkWarm.append(quad)
                }
            } else {
                switch summary.primaryClass {
                case .O, .B:
                    brightBlueWhite.append(quad)
                case .A, .whiteDwarf:
                    brightWhite.append(quad)
                case .F, .G:
                    brightYellow.append(quad)
                default:
                    brightOrangeRed.append(quad)
                }
            }
        }

        // 2. Deterministic procedural all-sky stars.
        var rng = SplitMix64(seed: seed ^ 0x57A2_F1E1_D001)

        // 650 medium-bright spectral-coloured stars across the sky.
        for _ in 0..<650 {
            let dir = randomSphereDirection(rng: &rng)
            let size = Float(rng.uniform(0.0026, 0.0044))
            let quad = StarQuad(direction: dir, angularSize: size)

            let roll = rng.unit()
            if roll < 0.14 {
                brightBlueWhite.append(quad)
            } else if roll < 0.42 {
                brightWhite.append(quad)
            } else if roll < 0.74 {
                brightYellow.append(quad)
            } else {
                brightOrangeRed.append(quad)
            }
        }

        // 1,600 faint pinpoint field stars for deep background density.
        for _ in 0..<1_600 {
            let dir = randomSphereDirection(rng: &rng)
            let size = Float(rng.uniform(0.0016, 0.0026))
            dimFieldStars.append(StarQuad(direction: dir, angularSize: size))
        }

        // 3. Milky Way galactic plane band (2,000 faint pinpoint stars concentrated near y = 0, denser toward +z Galactic Centre).
        for _ in 0..<2_000 {
            let towardsCore = rng.chance(0.58)
            let azimuth: Float
            if towardsCore {
                azimuth = Float.pi * 0.5 + Float(rng.uniform(-1.05, 1.05))
            } else {
                azimuth = Float(rng.uniform(0.0, 2.0 * .pi))
            }
            let latSpread = Float(rng.uniform(-0.20, 0.20) + rng.uniform(-0.20, 0.20))
            let raw = SIMD3<Float>(cos(azimuth), latSpread, sin(azimuth))
            let dir = simd_normalize(raw)
            let size = Float(rng.uniform(0.0015, 0.0027))
            milkyWayBandStars.append(StarQuad(direction: dir, angularSize: size))
        }

        let batches: [(String, [StarQuad], UIColor, Float, TextureResource?)] = [
            ("Stars_MilkyWayBand", milkyWayBandStars, UIColor(red: 0.62, green: 0.72, blue: 0.92, alpha: 1.0), 0.45, softTexture),
            ("Stars_DimField", dimFieldStars, UIColor(red: 0.85, green: 0.88, blue: 0.96, alpha: 1.0), 0.55, softTexture),
            ("Stars_BlueWhite", brightBlueWhite, UIColor(red: 0.68, green: 0.84, blue: 1.00, alpha: 1.0), 0.92, softTexture),
            ("Stars_White", brightWhite, UIColor(red: 0.96, green: 0.98, blue: 1.00, alpha: 1.0), 0.90, softTexture),
            ("Stars_Yellow", brightYellow, UIColor(red: 1.00, green: 0.93, blue: 0.76, alpha: 1.0), 0.90, softTexture),
            ("Stars_OrangeRed", brightOrangeRed, UIColor(red: 1.00, green: 0.72, blue: 0.50, alpha: 1.0), 0.88, softTexture),
            ("Stars_LandmarkCool", landmarkBlueWhite, UIColor(red: 0.80, green: 0.92, blue: 1.00, alpha: 1.0), 1.00, landmarkTexture),
            ("Stars_LandmarkWarm", landmarkWarm, UIColor(red: 1.00, green: 0.86, blue: 0.66, alpha: 1.0), 1.00, landmarkTexture),
        ]

        for (index, batch) in batches.enumerated() {
            // Slight radial offset per layer avoids depth fighting between overlapping sprites.
            let layerRadius: Float = 490.0 - Float(index) * 1.5
            if let entity = makeStarBatchEntity(
                name: batch.0,
                stars: batch.1,
                radius: layerRadius,
                color: batch.2,
                opacity: batch.3,
                texture: batch.4
            ) {
                root.addChild(entity)
            }
        }

        return root
    }

    private static func randomSphereDirection(rng: inout SplitMix64) -> SIMD3<Float> {
        let z = Float(rng.uniform(-1.0, 1.0))
        let phi = Float(rng.uniform(0.0, 2.0 * .pi))
        let rXY = sqrt(max(0.0, 1.0 - z * z))
        return SIMD3<Float>(rXY * cos(phi), z, rXY * sin(phi))
    }

    private static func makeStarBatchEntity(
        name: String,
        stars: [StarQuad],
        radius: Float,
        color: UIColor,
        opacity: Float,
        texture: TextureResource?
    ) -> ModelEntity? {
        guard !stars.isEmpty else { return nil }

        var positions: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(stars.count * 4)
        uvs.reserveCapacity(stars.count * 4)
        indices.reserveCapacity(stars.count * 12)

        for star in stars {
            let dir = star.direction
            let refUp: SIMD3<Float> = abs(dir.y) > 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
            let right = simd_normalize(simd_cross(refUp, dir))
            let up = simd_cross(dir, right)

            let center = dir * radius
            let half = radius * star.angularSize

            let base = UInt32(positions.count)
            positions.append(center - right * half + up * half)
            positions.append(center + right * half + up * half)
            positions.append(center + right * half - up * half)
            positions.append(center - right * half - up * half)

            uvs.append(SIMD2<Float>(0.0, 0.0))
            uvs.append(SIMD2<Float>(1.0, 0.0))
            uvs.append(SIMD2<Float>(1.0, 1.0))
            uvs.append(SIMD2<Float>(0.0, 1.0))

            indices.append(contentsOf: [
                base + 0, base + 1, base + 2,
                base + 0, base + 2, base + 3,
                base + 0, base + 2, base + 1,
                base + 0, base + 3, base + 2,
            ])
        }

        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)

        guard let mesh = try? MeshResource.generate(from: [descriptor]) else {
            return nil
        }

        var material = UnlitMaterial()
        if let texture {
            material.color = .init(tint: color, texture: .init(texture))
        } else {
            material.color = .init(tint: color)
        }
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = name
        return entity
    }

    /// Generates a radial pinpoint star glow texture in memory (optionally with 4-point diffraction spikes).
    private static func makeStarTexture(size: Int, withSpikes: Bool) -> TextureResource? {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let half = Float(size) * 0.5

        for py in 0..<size {
            for px in 0..<size {
                let dx = (Float(px) + 0.5 - half) / half
                let dy = (Float(py) + 0.5 - half) / half
                let r = sqrt(dx * dx + dy * dy)

                var intensity: Float = 0.0
                if r < 1.0 {
                    let edgeFade = max(0.0, 1.0 - r)
                    let core = exp(-r * r * (withSpikes ? 22.0 : 28.0))
                    let halo = (withSpikes ? 0.42 : 0.30) * exp(-r * r * 6.5) * edgeFade * edgeFade
                    intensity = core + halo

                    if withSpikes {
                        let horizSpike = exp(-abs(dy) * 20.0) * exp(-abs(dx) * 3.2) * edgeFade
                        let vertSpike = exp(-abs(dx) * 20.0) * exp(-abs(dy) * 3.2) * edgeFade
                        intensity += 0.55 * (horizSpike + vertSpike)
                    }
                }

                let clamped = min(1.0, max(0.0, intensity))
                let byteVal = UInt8((clamped * 255.0).rounded())
                let idx = (py * size + px) * 4
                pixels[idx + 0] = byteVal
                pixels[idx + 1] = byteVal
                pixels[idx + 2] = byteVal
                pixels[idx + 3] = byteVal
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                  width: size,
                  height: size,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: size * 4,
                  space: colorSpace,
                  bitmapInfo: bitmapInfo,
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else {
            return nil
        }

        return try? TextureResource(image: cgImage, options: .init(semantic: .color))
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

        let spaceBlack = UIColor(red: 0.006, green: 0.008, blue: 0.016, alpha: 1.0)
        let material = UnlitMaterial(color: spaceBlack)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "DeepSpaceBackdrop"
        return entity
    }
}
