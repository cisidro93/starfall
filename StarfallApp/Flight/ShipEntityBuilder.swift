import Foundation
import RealityKit
import UIKit
import simd

@MainActor
enum ShipEntityBuilder {

    struct BuiltShip {
        let hullID: String
        let root: Entity
        let exteriorRoot: Entity
        let cockpitInteriorRoot: Entity
        let leftPlume: ModelEntity
        let rightPlume: ModelEntity
    }

    static func makeKestrelShip() -> BuiltShip {
        makeShip(hullID: "sf1v_kestrel")
    }

    static func makeShip(hullID: String) -> BuiltShip {
        let root = Entity()
        root.name = "PlayerShip_\(hullID)"

        let exterior = Entity()
        exterior.name = "ShipExterior"
        root.addChild(exterior)

        let hullColor: UIColor
        let trimColor: UIColor
        let plumeColor: UIColor
        let hullScale: SIMD3<Float>

        switch hullID {
        case "sf2a_viper":
            hullColor = UIColor(red: 0.14, green: 0.16, blue: 0.24, alpha: 1.0)
            trimColor = UIColor(red: 1.00, green: 0.28, blue: 0.22, alpha: 1.0)
            plumeColor = UIColor(red: 0.35, green: 0.92, blue: 1.00, alpha: 1.0)
            hullScale = SIMD3<Float>(0.90, 0.92, 1.15)
        case "sf4c_cobra":
            hullColor = UIColor(red: 0.20, green: 0.24, blue: 0.30, alpha: 1.0)
            trimColor = UIColor(red: 0.20, green: 0.88, blue: 0.95, alpha: 1.0)
            plumeColor = UIColor(red: 0.22, green: 0.95, blue: 0.82, alpha: 1.0)
            hullScale = SIMD3<Float>(1.28, 1.05, 1.02)
        case "sf7t_atlas":
            hullColor = UIColor(red: 0.28, green: 0.24, blue: 0.18, alpha: 1.0)
            trimColor = UIColor(red: 0.98, green: 0.68, blue: 0.16, alpha: 1.0)
            plumeColor = UIColor(red: 1.00, green: 0.68, blue: 0.22, alpha: 1.0)
            hullScale = SIMD3<Float>(1.38, 1.35, 1.18)
        case "sf9x_astrolabe":
            hullColor = UIColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1.0)
            trimColor = UIColor(red: 0.96, green: 0.78, blue: 0.32, alpha: 1.0)
            plumeColor = UIColor(red: 0.45, green: 0.96, blue: 1.00, alpha: 1.0)
            hullScale = SIMD3<Float>(1.32, 1.18, 1.30)
        default:
            hullColor = UIColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1.0)
            trimColor = UIColor(red: 0.85, green: 0.60, blue: 0.28, alpha: 1.0)
            plumeColor = UIColor(red: 0.25, green: 0.85, blue: 1.0, alpha: 1.0)
            hullScale = SIMD3<Float>(1.0, 1.0, 1.0)
        }

        var armorMat = SimpleMaterial()
        if let hullTex = SolSceneBuilder.loadAssetTexture("tex_ship_hull_plating") {
            armorMat.color = .init(tint: hullColor.withAlphaComponent(1.0), texture: .init(hullTex))
        } else {
            armorMat.color = .init(tint: hullColor)
        }
        armorMat.roughness = .init(floatLiteral: 0.30)
        armorMat.metallic = .init(floatLiteral: 0.88)
        let accentMat = SimpleMaterial(
            color: trimColor,
            roughness: 0.22,
            isMetallic: true
        )
        let darkAlloy = SimpleMaterial(
            color: UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1.0),
            roughness: 0.50,
            isMetallic: true
        )
        let canopyGlass = SimpleMaterial(
            color: UIColor(red: 0.10, green: 0.24, blue: 0.36, alpha: 0.85),
            roughness: 0.08,
            isMetallic: false
        )

        if let hullMesh = makeDeltaHullMesh() {
            let hull = ModelEntity(mesh: hullMesh, materials: [armorMat])
            hull.name = "DeltaHull"
            hull.scale = hullScale
            exterior.addChild(hull)
        }

        let trimMesh = MeshResource.generateBox(size: SIMD3<Float>(0.18, 0.09, 4.8), cornerRadius: 0.02)
        let leftTrim = ModelEntity(mesh: trimMesh, materials: [accentMat])
        leftTrim.position = SIMD3<Float>(-1.75 * hullScale.x, 0.02, -0.3)
        leftTrim.orientation = simd_quatf(angle: -0.46, axis: SIMD3<Float>(0, 1, 0))
        exterior.addChild(leftTrim)

        let rightTrim = ModelEntity(mesh: trimMesh, materials: [accentMat])
        rightTrim.position = SIMD3<Float>(1.75 * hullScale.x, 0.02, -0.3)
        rightTrim.orientation = simd_quatf(angle: 0.46, axis: SIMD3<Float>(0, 1, 0))
        exterior.addChild(rightTrim)

        let canopyMesh = MeshResource.generateBox(size: SIMD3<Float>(0.92, 0.46, 2.3), cornerRadius: 0.22)
        let canopy = ModelEntity(mesh: canopyMesh, materials: [canopyGlass])
        canopy.position = SIMD3<Float>(0.0, 0.36 * hullScale.y, -0.65)
        exterior.addChild(canopy)

        let finMesh = MeshResource.generateBox(size: SIMD3<Float>(0.10, 0.85, 1.45), cornerRadius: 0.03)
        let leftFin = ModelEntity(mesh: finMesh, materials: [accentMat])
        leftFin.position = SIMD3<Float>(-1.15 * hullScale.x, 0.45, 1.85)
        leftFin.orientation = simd_quatf(angle: 0.28, axis: SIMD3<Float>(0, 0, 1))
        exterior.addChild(leftFin)

        let rightFin = ModelEntity(mesh: finMesh, materials: [accentMat])
        rightFin.position = SIMD3<Float>(1.15 * hullScale.x, 0.45, 1.85)
        rightFin.orientation = simd_quatf(angle: -0.28, axis: SIMD3<Float>(0, 0, 1))
        exterior.addChild(rightFin)

        let nozzleMesh = MeshResource.generateBox(size: SIMD3<Float>(0.78, 0.52, 0.90), cornerRadius: 0.12)
        let leftNozzle = ModelEntity(mesh: nozzleMesh, materials: [darkAlloy])
        leftNozzle.position = SIMD3<Float>(-0.72, 0.0, 2.55)
        exterior.addChild(leftNozzle)

        let rightNozzle = ModelEntity(mesh: nozzleMesh, materials: [darkAlloy])
        rightNozzle.position = SIMD3<Float>(0.72, 0.0, 2.55)
        exterior.addChild(rightNozzle)

        let plumeMesh = MeshResource.generateSphere(radius: 0.34)
        let plumeMat = UnlitMaterial(color: plumeColor)

        let leftPlume = ModelEntity(mesh: plumeMesh, materials: [plumeMat])
        leftPlume.position = SIMD3<Float>(-0.72, 0.0, 3.15)
        leftPlume.scale = SIMD3<Float>(0.85, 0.65, 1.8)
        exterior.addChild(leftPlume)

        let rightPlume = ModelEntity(mesh: plumeMesh, materials: [plumeMat])
        rightPlume.position = SIMD3<Float>(0.72, 0.0, 3.15)
        rightPlume.scale = SIMD3<Float>(0.85, 0.65, 1.8)
        exterior.addChild(rightPlume)

        let cockpitInterior = makeCockpitInterior(hullID: hullID, accentColor: trimColor)
        root.addChild(cockpitInterior)

        return BuiltShip(
            hullID: hullID,
            root: root,
            exteriorRoot: exterior,
            cockpitInteriorRoot: cockpitInterior,
            leftPlume: leftPlume,
            rightPlume: rightPlume
        )
    }

    private static func makeCockpitInterior(hullID: String, accentColor: UIColor) -> Entity {
        let interior = Entity()
        interior.name = "CockpitInteriorFrame"

        let strutMat = SimpleMaterial(
            color: UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1.0),
            roughness: 0.6,
            isMetallic: true
        )
        let dashMat = SimpleMaterial(
            color: UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1.0),
            roughness: 0.75,
            isMetallic: false
        )
        let holoAccent = UnlitMaterial(color: accentColor)
        let holoCyan = UnlitMaterial(color: UIColor(red: 0.20, green: 0.86, blue: 1.00, alpha: 1.0))

        // Forward lower dashboard coaming below sightline
        let dashMesh = MeshResource.generateBox(size: SIMD3<Float>(1.65, 0.24, 0.75), cornerRadius: 0.05)
        let dash = ModelEntity(mesh: dashMesh, materials: [dashMat])
        dash.position = SIMD3<Float>(0.0, -0.44, -1.15)
        interior.addChild(dash)

        let stripMesh = MeshResource.generateBox(size: SIMD3<Float>(0.90, 0.014, 0.025))
        let centerStrip = ModelEntity(mesh: stripMesh, materials: [holoAccent])
        centerStrip.position = SIMD3<Float>(0.0, -0.31, -0.92)
        interior.addChild(centerStrip)

        let sideStripMesh = MeshResource.generateBox(size: SIMD3<Float>(0.28, 0.010, 0.02))
        let leftCyanStrip = ModelEntity(mesh: sideStripMesh, materials: [holoCyan])
        leftCyanStrip.position = SIMD3<Float>(-0.56, -0.31, -0.96)
        leftCyanStrip.orientation = simd_quatf(angle: 0.25, axis: SIMD3<Float>(0, 1, 0))
        interior.addChild(leftCyanStrip)

        let rightCyanStrip = ModelEntity(mesh: sideStripMesh, materials: [holoCyan])
        rightCyanStrip.position = SIMD3<Float>(0.56, -0.31, -0.96)
        rightCyanStrip.orientation = simd_quatf(angle: -0.25, axis: SIMD3<Float>(0, 1, 0))
        interior.addChild(rightCyanStrip)

        let pillarSpread: Float = (hullID == "sf4c_cobra" || hullID == "sf7t_atlas") ? 0.80 : 0.68
        let pillarMesh = MeshResource.generateBox(size: SIMD3<Float>(0.045, 0.95, 0.055), cornerRadius: 0.01)
        let leftPillar = ModelEntity(mesh: pillarMesh, materials: [strutMat])
        leftPillar.position = SIMD3<Float>(-pillarSpread, 0.05, -1.05)
        let leftTiltZ = simd_quatf(angle: -0.28, axis: SIMD3<Float>(0, 0, 1))
        let leftTiltX = simd_quatf(angle: 0.42, axis: SIMD3<Float>(1, 0, 0))
        leftPillar.orientation = simd_mul(leftTiltZ, leftTiltX)
        interior.addChild(leftPillar)

        let rightPillar = ModelEntity(mesh: pillarMesh, materials: [strutMat])
        rightPillar.position = SIMD3<Float>(pillarSpread, 0.05, -1.05)
        let rightTiltZ = simd_quatf(angle: 0.28, axis: SIMD3<Float>(0, 0, 1))
        let rightTiltX = simd_quatf(angle: 0.42, axis: SIMD3<Float>(1, 0, 0))
        rightPillar.orientation = simd_mul(rightTiltZ, rightTiltX)
        interior.addChild(rightPillar)

        let headerMesh = MeshResource.generateBox(size: SIMD3<Float>(pillarSpread * 1.85, 0.04, 0.05), cornerRadius: 0.01)
        let header = ModelEntity(mesh: headerMesh, materials: [strutMat])
        header.position = SIMD3<Float>(0.0, 0.46, -0.88)
        interior.addChild(header)

        return interior
    }

    private static func makeDeltaHullMesh() -> MeshResource? {
        let nose = SIMD3<Float>(0.0, 0.0, -3.6)
        let topSpineFwd = SIMD3<Float>(0.0, 0.38, -1.4)
        let topSpineAft = SIMD3<Float>(0.0, 0.42, 2.4)
        let bellyFwd = SIMD3<Float>(0.0, -0.28, -1.5)
        let bellyAft = SIMD3<Float>(0.0, -0.30, 2.5)
        let leftWingTip = SIMD3<Float>(-3.4, -0.05, 2.1)
        let rightWingTip = SIMD3<Float>(3.4, -0.05, 2.1)
        let leftRear = SIMD3<Float>(-1.35, 0.12, 2.7)
        let rightRear = SIMD3<Float>(1.35, 0.12, 2.7)

        let rawTriangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            (nose, leftWingTip, topSpineFwd),
            (nose, topSpineFwd, rightWingTip),
            (topSpineFwd, leftWingTip, leftRear),
            (topSpineFwd, leftRear, topSpineAft),
            (topSpineFwd, topSpineAft, rightRear),
            (topSpineFwd, rightRear, rightWingTip),
            (nose, bellyFwd, leftWingTip),
            (nose, rightWingTip, bellyFwd),
            (bellyFwd, bellyAft, leftWingTip),
            (bellyAft, leftRear, leftWingTip),
            (bellyFwd, rightWingTip, bellyAft),
            (bellyAft, rightWingTip, rightRear),
            (topSpineAft, leftRear, bellyAft),
            (topSpineAft, bellyAft, rightRear),
        ]

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for (a, b, c) in rawTriangles {
            let e1 = b - a
            let e2 = c - a
            let n = simd_normalize(simd_cross(e1, e2))
            let base = UInt32(positions.count)
            positions.append(contentsOf: [a, b, c])
            normals.append(contentsOf: [n, n, n])
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 1])
        }

        var descriptor = MeshDescriptor(name: "KestrelDeltaHull")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)

        return try? MeshResource.generate(from: [descriptor])
    }
}
