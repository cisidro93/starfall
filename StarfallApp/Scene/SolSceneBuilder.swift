import Foundation
import RealityKit
import UIKit
import CoreGraphics
import simd
import StarfallGalaxy

@MainActor
enum SolSceneBuilder {

    struct BuiltSolEnvironment {
        let stationEntity: Entity
        let rotatingWheelEntity: Entity
        let planetaryEntities: [Entity]
        let dustParticles: [Entity]
        let dustOffsets: [SIMD3<Float>]
        let stationName: String
        let stationWorldPosition: SIMD3<Double>
        let earthWorldPosition: SIMD3<Double>
        let earthRadiusMetres: Double
        let moonWorldPosition: SIMD3<Double>
        let sunWorldPosition: SIMD3<Double>
    }

    static func buildSolEnvironment(into root: Entity) -> BuiltSolEnvironment {
        let galaxy = Galaxy()
        let solSystem = galaxy.system(galaxy.sol.id)!

        let solStar = solSystem.stars.first!
        let earthBody = solSystem.bodies.first { $0.name == "Earth" }!
        let moonBody = earthBody.moons.first { $0.name == "Moon" }!
        let gagarinStation = solSystem.settlement?.stations.first { $0.orbiting == "Earth" }

        let stationTitle = gagarinStation?.name ?? "Gagarin Gateway"

        // True radii in metres from StarfallGalaxy
        let earthRadiusM = earthBody.radiusKm * 1_000.0
        let moonRadiusM = moonBody.radiusKm * 1_000.0
        let sunRadiusM = solStar.radiusSolar * 696_340_000.0

        // Player spawns at (0, 0, 0) in high orbit above Earth (~9,100 km above surface, 15,500 km from Earth's centre)
        let earthDir = simd_normalize(SIMD3<Double>(-0.48, -0.16, -0.86))
        let earthWorldPos = earthDir * (earthRadiusM + 9_100_000.0)

        // Moon at true 384,400 km from Earth
        let moonDir = simd_normalize(SIMD3<Double>(0.52, 0.22, -0.82))
        let moonWorldPos = earthWorldPos + moonDir * (moonBody.semiMajorAxisKm * 1_000.0)

        // Sun at true 1.0 AU (149.6M km) in upper-right forward quadrant
        let sunDir = simd_normalize(SIMD3<Double>(0.74, 0.32, -0.59))
        let sunWorldPos = sunDir * (earthBody.semiMajorAxisKm * 1_000.0)

        // 1. Directional sunlight aligned with the Sun's true direction
        let sunLightEntity = Entity()
        sunLightEntity.name = "SolDirectionalLight"
        let dirLight = DirectionalLightComponent(
            color: UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1.0),
            intensity: 3_200
        )
        sunLightEntity.components.set(dirLight)
        sunLightEntity.look(
            at: .zero,
            from: SIMD3<Float>(Float(sunDir.x), Float(sunDir.y), Float(sunDir.z)) * 10.0,
            relativeTo: nil
        )
        root.addChild(sunLightEntity)

        // Subtle fill light from Earth's day-side albedo glow so shadow sides have rich contrast
        let earthshineLight = Entity()
        earthshineLight.name = "EarthshineFillLight"
        let fillLight = DirectionalLightComponent(
            color: UIColor(red: 0.25, green: 0.50, blue: 0.85, alpha: 1.0),
            intensity: 380
        )
        earthshineLight.components.set(fillLight)
        earthshineLight.look(
            at: .zero,
            from: SIMD3<Float>(Float(earthDir.x), Float(earthDir.y), Float(earthDir.z)) * 10.0,
            relativeTo: nil
        )
        root.addChild(earthshineLight)

        // 2. Build Sun, Earth, and Moon planetary proxy entities
        var planetaryEntities: [Entity] = []

        let sunEntity = makeSunEntity(worldPosition: sunWorldPos, trueRadiusMetres: sunRadiusM)
        root.addChild(sunEntity)
        planetaryEntities.append(sunEntity)

        let earthEntity = makeEarthEntity(worldPosition: earthWorldPos, trueRadiusMetres: earthRadiusM)
        root.addChild(earthEntity)
        planetaryEntities.append(earthEntity)

        let moonEntity = makeMoonEntity(worldPosition: moonWorldPos, trueRadiusMetres: moonRadiusM)
        root.addChild(moonEntity)
        planetaryEntities.append(moonEntity)

        // 3. Build Gagarin Gateway ring station 900 m ahead of player spawn
        let stationWorldPos = SIMD3<Double>(0.0, 0.0, -900.0)
        let (stationEntity, rotatingWheel) = makeRingStationEntity(
            name: stationTitle,
            worldPosition: stationWorldPos
        )
        root.addChild(stationEntity)

        // 4. Build approach corridor navigation buoys leading toward the docking slot
        makeApproachBuoys(into: root, stationWorldPos: stationWorldPos)

        // 5. Build space-dust speed reference particles around player
        let (dustEntities, dustOffsets) = makeSpaceDustPool(into: root, count: 75,seed: galaxy.seed)

        return BuiltSolEnvironment(
            stationEntity: stationEntity,
            rotatingWheelEntity: rotatingWheel,
            planetaryEntities: planetaryEntities,
            dustParticles: dustEntities,
            dustOffsets: dustOffsets,
            stationName: stationTitle,
            stationWorldPosition: stationWorldPos,
            earthWorldPosition: earthWorldPos,
            earthRadiusMetres: earthRadiusM,
            moonWorldPosition: moonWorldPos,
            sunWorldPosition: sunWorldPos
        )
    }

    // MARK: - Sun, Earth & Moon

    private static func makeSunEntity(worldPosition: SIMD3<Double>, trueRadiusMetres: Double) -> Entity {
        let container = Entity()
        container.name = "PlanetProxy_Sun"
        container.components.set(
            PlanetaryBodyComponent(
                bodyName: "Sol",
                worldPosition: worldPosition,
                trueRadiusMetres: trueRadiusMetres,
                proxyDistanceMetres: 3_600.0
            )
        )

        // Unit-radius sphere scaled dynamically by PlanetaryBodyComponent
        let coreMesh = MeshResource.generateSphere(radius: 1.0)
        let coreMat = UnlitMaterial(color: UIColor(red: 1.0, green: 0.96, blue: 0.82, alpha: 1.0))
        let core = ModelEntity(mesh: coreMesh, materials: [coreMat])
        container.addChild(core)

        // Corona glow shells
        let innerGlowMesh = MeshResource.generateSphere(radius: 1.65)
        var innerGlowMat = UnlitMaterial(color: UIColor(red: 1.0, green: 0.80, blue: 0.35, alpha: 1.0))
        innerGlowMat.blending = .transparent(opacity: .init(floatLiteral: 0.38))
        let innerGlow = ModelEntity(mesh: innerGlowMesh, materials: [innerGlowMat])
        container.addChild(innerGlow)

        let outerGlowMesh = MeshResource.generateSphere(radius: 2.8)
        var outerGlowMat = UnlitMaterial(color: UIColor(red: 1.0, green: 0.58, blue: 0.16, alpha: 1.0))
        outerGlowMat.blending = .transparent(opacity: .init(floatLiteral: 0.16))
        let outerGlow = ModelEntity(mesh: outerGlowMesh, materials: [outerGlowMat])
        container.addChild(outerGlow)

        return container
    }

    private static func makeEarthEntity(worldPosition: SIMD3<Double>, trueRadiusMetres: Double) -> Entity {
        let container = Entity()
        container.name = "PlanetProxy_Earth"
        container.components.set(
            PlanetaryBodyComponent(
                bodyName: "Earth",
                worldPosition: worldPosition,
                trueRadiusMetres: trueRadiusMetres,
                proxyDistanceMetres: 2_200.0
            )
        )

        let sphereMesh = MeshResource.generateSphere(radius: 1.0)
        var earthMaterial = SimpleMaterial()
        if let tex = makeProceduralEarthTexture(width: 256, height: 128) {
            earthMaterial.color = .init(tint: .white, texture: .init(tex))
        } else {
            earthMaterial.color = .init(tint: UIColor(red: 0.14, green: 0.42, blue: 0.78, alpha: 1.0))
        }
        earthMaterial.roughness = .init(floatLiteral: 0.65)
        earthMaterial.metallic = .init(floatLiteral: 0.08)

        let globe = ModelEntity(mesh: sphereMesh, materials: [earthMaterial])
        // Tilt Earth's axial obliquity (23.4°)
        globe.orientation = simd_quatf(angle: 0.41, axis: simd_normalize(SIMD3<Float>(0.2, 1.0, 0.3)))
        container.addChild(globe)

        // Translucent cyan atmosphere rim shell
        let atmoMesh = MeshResource.generateSphere(radius: 1.032)
        var atmoMat = UnlitMaterial(color: UIColor(red: 0.32, green: 0.72, blue: 1.0, alpha: 1.0))
        atmoMat.blending = .transparent(opacity: .init(floatLiteral: 0.18))
        let atmo = ModelEntity(mesh: atmoMesh, materials: [atmoMat])
        container.addChild(atmo)

        return container
    }

    private static func makeMoonEntity(worldPosition: SIMD3<Double>, trueRadiusMetres: Double) -> Entity {
        let container = Entity()
        container.name = "PlanetProxy_Moon"
        container.components.set(
            PlanetaryBodyComponent(
                bodyName: "Moon",
                worldPosition: worldPosition,
                trueRadiusMetres: trueRadiusMetres,
                proxyDistanceMetres: 2_900.0
            )
        )

        let sphereMesh = MeshResource.generateSphere(radius: 1.0)
        let moonMaterial = SimpleMaterial(
            color: UIColor(red: 0.68, green: 0.69, blue: 0.72, alpha: 1.0),
            roughness: 0.92,
            isMetallic: false
        )
        let moonModel = ModelEntity(mesh: sphereMesh, materials: [moonMaterial])
        container.addChild(moonModel)

        return container
    }

    // MARK: - Gagarin Gateway Ring Station

    private static func makeRingStationEntity(
        name: String,
        worldPosition: SIMD3<Double>
    ) -> (Entity, Entity) {
        let stationRoot = Entity()
        stationRoot.name = name
        stationRoot.components.set(WorldPositionComponent(worldPosition))

        let rotatingWheel = Entity()
        rotatingWheel.name = "RotatingHabitatWheel"
        stationRoot.addChild(rotatingWheel)

        let hullSteel = SimpleMaterial(
            color: UIColor(red: 0.24, green: 0.27, blue: 0.32, alpha: 1.0),
            roughness: 0.40,
            isMetallic: true
        )
        let darkArmor = SimpleMaterial(
            color: UIColor(red: 0.13, green: 0.15, blue: 0.19, alpha: 1.0),
            roughness: 0.52,
            isMetallic: true
        )
        let goldAccent = SimpleMaterial(
            color: UIColor(red: 0.86, green: 0.62, blue: 0.28, alpha: 1.0),
            roughness: 0.28,
            isMetallic: true
        )
        let windowGlow = UnlitMaterial(color: UIColor(red: 1.0, green: 0.88, blue: 0.65, alpha: 1.0))
        let dockSlotGlow = UnlitMaterial(color: UIColor(red: 0.18, green: 0.88, blue: 1.0, alpha: 1.0))
        let greenNav = UnlitMaterial(color: UIColor(red: 0.20, green: 0.95, blue: 0.45, alpha: 1.0))
        let redNav = UnlitMaterial(color: UIColor(red: 1.00, green: 0.25, blue: 0.25, alpha: 1.0))

        // Central docking core cylinder (aligned along Z axis so docking slot faces +Z toward player)
        let coreBodyMesh = MeshResource.generateBox(size: SIMD3<Float>(54.0, 54.0, 96.0), cornerRadius: 12.0)
        let coreBody = ModelEntity(mesh: coreBodyMesh, materials: [darkArmor])
        rotatingWheel.addChild(coreBody)

        // Glowing "Mail-Slot" docking bay entrance on the +Z face of the central hub
        let slotFrameMesh = MeshResource.generateBox(size: SIMD3<Float>(28.0, 10.0, 2.5), cornerRadius: 1.0)
        let slotFrame = ModelEntity(mesh: slotFrameMesh, materials: [goldAccent])
        slotFrame.position = SIMD3<Float>(0.0, 0.0, 48.0)
        rotatingWheel.addChild(slotFrame)

        let slotInteriorMesh = MeshResource.generateBox(size: SIMD3<Float>(24.0, 6.8, 3.2))
        let slotInterior = ModelEntity(mesh: slotInteriorMesh, materials: [dockSlotGlow])
        slotInterior.position = SIMD3<Float>(0.0, 0.0, 48.2)
        rotatingWheel.addChild(slotInterior)

        // Port (red) and Starboard (green) docking slot guide lights
        let beaconMesh = MeshResource.generateSphere(radius: 1.4)
        let leftBeacon = ModelEntity(mesh: beaconMesh, materials: [redNav])
        leftBeacon.position = SIMD3<Float>(-16.5, 0.0, 49.0)
        rotatingWheel.addChild(leftBeacon)

        let rightBeacon = ModelEntity(mesh: beaconMesh, materials: [greenNav])
        rightBeacon.position = SIMD3<Float>(16.5, 0.0, 49.0)
        rotatingWheel.addChild(rightBeacon)

        // 4 radial structural spokes connecting the docking hub to the 160m-radius habitat ring
        let ringRadius: Float = 155.0
        let spokeLength: Float = ringRadius * 2.0 - 16.0
        let spokeMesh = MeshResource.generateBox(size: SIMD3<Float>(8.0, spokeLength, 10.0), cornerRadius: 1.5)
        for s in 0..<2 {
            let angle = Float(s) * (.pi * 0.5)
            let spoke = ModelEntity(mesh: spokeMesh, materials: [hullSteel])
            spoke.orientation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 0, 1))
            rotatingWheel.addChild(spoke)
        }

        // 16-segment outer rotating habitat ring + lit interior window band
        let segmentCount = 16
        let chordLength = 2.0 * ringRadius * sin(.pi / Float(segmentCount)) * 1.06
        let segMesh = MeshResource.generateBox(size: SIMD3<Float>(chordLength, 22.0, 34.0), cornerRadius: 3.5)
        let winMesh = MeshResource.generateBox(size: SIMD3<Float>(chordLength * 0.78, 2.2, 8.0))
        let trimSegMesh = MeshResource.generateBox(size: SIMD3<Float>(chordLength * 0.92, 2.5, 36.0))

        for i in 0..<segmentCount {
            let theta = (Float(i) / Float(segmentCount)) * 2.0 * .pi
            let x = cos(theta) * ringRadius
            let y = sin(theta) * ringRadius

            let seg = ModelEntity(mesh: segMesh, materials: [hullSteel])
            seg.position = SIMD3<Float>(x, y, 0.0)
            seg.orientation = simd_quatf(angle: theta + .pi * 0.5, axis: SIMD3<Float>(0, 0, 1))
            rotatingWheel.addChild(seg)

            // Lit inward-facing habitat windows
            let winR = ringRadius - 11.2
            let win = ModelEntity(mesh: winMesh, materials: [windowGlow])
            win.position = SIMD3<Float>(cos(theta) * winR, sin(theta) * winR, 0.0)
            win.orientation = simd_quatf(angle: theta + .pi * 0.5, axis: SIMD3<Float>(0, 0, 1))
            rotatingWheel.addChild(win)

            if i % 2 == 0 {
                let trim = ModelEntity(mesh: trimSegMesh, materials: [goldAccent])
                trim.position = SIMD3<Float>(x, y, 0.0)
                trim.orientation = simd_quatf(angle: theta + .pi * 0.5, axis: SIMD3<Float>(0, 0, 1))
                rotatingWheel.addChild(trim)
            }
        }

        return (stationRoot, rotatingWheel)
    }

    private static func makeApproachBuoys(into root: Entity, stationWorldPos: SIMD3<Double>) {
        let buoyMat = UnlitMaterial(color: UIColor(red: 0.18, green: 0.90, blue: 0.75, alpha: 1.0))
        let buoyMesh = MeshResource.generateSphere(radius: 1.1)

        // 5 pairs of approach corridor buoys between z = -220m and z = -740m
        for idx in 0..<5 {
            let zWorld = -220.0 - Double(idx) * 130.0
            for side in [-1.0, 1.0] {
                let buoy = ModelEntity(mesh: buoyMesh, materials: [buoyMat])
                buoy.name = "ApproachBuoy_\(idx)_\(side < 0 ? "L" : "R")"
                buoy.components.set(
                    WorldPositionComponent(
                        x: stationWorldPos.x + side * 32.0,
                        y: stationWorldPos.y,
                        z: zWorld
                    )
                )
                root.addChild(buoy)
            }
        }
    }

    private static func makeSpaceDustPool(
        into root: Entity,
        count: Int,
        seed: UInt64
    ) -> ([Entity], [SIMD3<Float>]) {
        var rng = SplitMix64(seed: seed ^ 0xD057_F1E1)
        let dustMesh = MeshResource.generateSphere(radius: 0.075)
        var dustMat = UnlitMaterial(color: UIColor(red: 0.72, green: 0.88, blue: 1.0, alpha: 1.0))
        dustMat.blending = .transparent(opacity: .init(floatLiteral: 0.55))

        var entities: [Entity] = []
        var offsets: [SIMD3<Float>] = []
        entities.reserveCapacity(count)
        offsets.reserveCapacity(count)

        for i in 0..<count {
            let offset = SIMD3<Float>(
                Float(rng.uniform(-70.0, 70.0)),
                Float(rng.uniform(-70.0, 70.0)),
                Float(rng.uniform(-70.0, 70.0))
            )
            let mote = ModelEntity(mesh: dustMesh, materials: [dustMat])
            mote.name = "SpaceDust_\(i)"
            mote.position = offset
            root.addChild(mote)
            entities.append(mote)
            offsets.append(offset)
        }

        return (entities, offsets)
    }

    // MARK: - Procedural Earth Texture

    private static func makeProceduralEarthTexture(width: Int, height: Int) -> TextureResource? {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)

        for py in 0..<height {
            let v = Double(py) / Double(height - 1)
            let lat = (0.5 - v) * .pi // +pi/2 north pole to -pi/2 south pole
            let cosLat = cos(lat)
            let sinLat = sin(lat)
            let absLat = abs(lat)

            for px in 0..<width {
                let u = Double(px) / Double(width)
                let lon = u * 2.0 * .pi

                let nx = cosLat * cos(lon)
                let ny = sinLat
                let nz = cosLat * sin(lon)

                // Multi-frequency trigonometric continent approximation (deterministic & fast)
                let n1 = sin(nx * 2.6 + 0.4) * cos(ny * 2.9 - 0.3) + cos(nz * 2.4 + 1.1)
                let n2 = 0.5 * sin(nx * 6.2 - nz * 4.8) * cos(ny * 5.5 + 0.7)
                let n3 = 0.25 * cos(nx * 13.0 + ny * 11.0 - nz * 9.0)
                let elevation = (n1 + n2 + n3) * 0.45

                // Cloud swirl layer
                let cloudWave = sin(lon * 5.0 + sin(lat * 4.0) * 1.6) * cos(lat * 6.5 + cos(lon * 3.0))
                let cloud = max(0.0, cloudWave - 0.28) * 0.85

                var r: Double
                var g: Double
                var b: Double

                if absLat > 1.25 - elevation * 0.12 {
                    // Polar ice caps
                    r = 0.90; g = 0.94; b = 0.98
                } else if elevation > 0.12 {
                    // Continents: coastal emerald green blending to arid ochre/mountain highlands
                    let h = min(1.0, (elevation - 0.12) / 0.65)
                    r = 0.16 + 0.42 * h
                    g = 0.42 + 0.14 * (1.0 - abs(h - 0.4))
                    b = 0.14 + 0.08 * h
                } else {
                    // Deep ocean to shallow continental shelf
                    let shelf = max(0.0, (elevation + 0.25) / 0.37)
                    r = 0.04 + 0.06 * shelf
                    g = 0.16 + 0.24 * shelf
                    b = 0.44 + 0.28 * shelf
                }

                // Blend atmospheric clouds over surface
                r = min(1.0, r * (1.0 - cloud) + 0.96 * cloud)
                g = min(1.0, g * (1.0 - cloud) + 0.98 * cloud)
                b = min(1.0, b * (1.0 - cloud) + 1.00 * cloud)

                let idx = (py * width + px) * 4
                pixels[idx + 0] = UInt8((r * 255.0).rounded())
                pixels[idx + 1] = UInt8((g * 255.0).rounded())
                pixels[idx + 2] = UInt8((b * 255.0).rounded())
                pixels[idx + 3] = 255
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
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
}
