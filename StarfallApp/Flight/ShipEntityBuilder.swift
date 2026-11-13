import Foundation
import RealityKit
import UIKit
import simd

@MainActor
enum ShipEntityBuilder {

    struct BuiltShip {
        let root: Entity
        let exteriorRoot: Entity
        let cockpitInteriorRoot: Entity
        let leftPlume: ModelEntity
        let rightPlume: ModelEntity
    }

    static func makeKestrelShip() -> BuiltShip {
        let root = Entity()
        root.name = "PlayerShip_Kestrel"

        let exterior = Entity()
        exterior.name = "ShipExterior"
        root.addChild(exterior)

        let gunmetal = SimpleMaterial(
            color: UIColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1.0),
            roughness: 0.32,
            isMetallic: true
        )
        let bronzeGold = SimpleMaterial(
            color: UIColor(red: 0.85, green: 0.60, blue: 0.28, alpha: 1.0),
            roughness: 0.25,
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

        // Custom faceted delta-wedge hull mesh (pointing forward along -Z)
        if let hullMesh = makeDeltaHullMesh() {
            let hull = ModelEntity(mesh: hullMesh, materials: [gunmetal])
            hull.name = "DeltaHull"
            exterior.addChild(hull)
        }

        // Gold chevron wing trim bars matching the Starfall emblem aesthetic
        let trimMesh = MeshResource.generateBox(size: SIMD3<Float>(0.16, 0.08, 4.8), cornerRadius: 0.02)
        let leftTrim = ModelEntity(mesh: trimMesh, materials: [bronzeGold])
        leftTrim.position = SIMD3<Float>(-1.75, 0.02, -0.3)
        leftTrim.orientation = simd_quatf(angle: -0.46, axis: SIMD3<Float>(0, 1, 0))
        exterior.addChild(leftTrim)

        let rightTrim = ModelEntity(mesh: trimMesh, materials: [bronzeGold])
        rightTrim.position = SIMD3<Float>(1.75, 0.02, -0.3)
        rightTrim.orientation = simd_quatf(angle: 0.46, axis: SIMD3<Float>(0, 1, 0))
        exterior.addChild(rightTrim)

        // Cockpit canopy blister on top deck
        let canopyMesh = MeshResource.generateBox(size: SIMD3<Float>(0.92, 0.46, 2.3), cornerRadius: 0.22)
        let canopy = ModelEntity(mesh: canopyMesh, materials: [canopyGlass])
        canopy.position = SIMD3<Float>(0.0, 0.36, -0.65)
        exterior.addChild(canopy)

        // Twin canted vertical stabilisers
        let finMesh = MeshResource.generateBox(size: SIMD3<Float>(0.10, 0.85, 1.45), cornerRadius: 0.03)
        let leftFin = ModelEntity(mesh: finMesh, materials: [bronzeGold])
        leftFin.position = SIMD3<Float>(-1.15, 0.45, 1.85)
        leftFin.orientation = simd_quatf(angle: 0.28, axis: SIMD3<Float>(0, 0, 1))
        exterior.addChild(leftFin)

        let rightFin = ModelEntity(mesh: finMesh, materials: [bronzeGold])
        rightFin.position = SIMD3<Float>(1.15, 0.45, 1.85)
        rightFin.orientation = simd_quatf(angle: -0.28, axis: SIMD3<Float>(0, 0, 1))
        exterior.addChild(rightFin)

        // Twin rear thruster housings
        let nozzleMesh = MeshResource.generateBox(size: SIMD3<Float>(0.78, 0.52, 0.90), cornerRadius: 0.12)
        let leftNozzle = ModelEntity(mesh: nozzleMesh, materials: [darkAlloy])
        leftNozzle.position = SIMD3<Float>(-0.72, 0.0, 2.55)
        exterior.addChild(leftNozzle)

        let rightNozzle = ModelEntity(mesh: nozzleMesh, materials: [darkAlloy])
        rightNozzle.position = SIMD3<Float>(0.72, 0.0, 2.55)
        exterior.addChild(rightNozzle)

        // Glowing engine exhaust plumes (+Z is aft)
        let plumeMesh = MeshResource.generateSphere(radius: 0.34)
        let plumeMat = UnlitMaterial(color: UIColor(red: 0.25, green: 0.85, blue: 1.0, alpha: 1.0))

        let leftPlume = ModelEntity(mesh: plumeMesh, materials: [plumeMat])
        leftPlume.position = SIMD3<Float>(-0.72, 0.0, 3.15)
        leftPlume.scale = SIMD3<Float>(0.85, 0.65, 1.8)
        exterior.addChild(leftPlume)

        let rightPlume = ModelEntity(mesh: plumeMesh, materials: [plumeMat])
        rightPlume.position = SIMD3<Float>(0.72, 0.0, 3.15)
        rightPlume.scale = SIMD3<Float>(0.85, 0.65, 1.8)
        exterior.addChild(rightPlume)

        // Cockpit interior frame (visible in First-Person Cockpit camera mode)
        let cockpitInterior = makeCockpitInterior()
        root.addChild(cockpitInterior)

        return BuiltShip(
            root: root,
            exteriorRoot: exterior,
            cockpitInteriorRoot: cockpitInterior,
            leftPlume: leftPlume,
            rightPlume: rightPlume
        )
    }

    private static func makeCockpitInterior() -> Entity {
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
        let holoAmber = UnlitMaterial(color: UIColor(red: 0.98, green: 0.62, blue: 0.18, alpha: 1.0))
        let holoCyan = UnlitMaterial(color: UIColor(red: 0.20, green: 0.86, blue: 1.00, alpha: 1.0))

        // Forward lower dashboard coaming below sightline
        let dashMesh = MeshResource.generateBox(size: SIMD3<Float>(1.65, 0.24, 0.75), cornerRadius: 0.05)
        let dash = ModelEntity(mesh: dashMesh, materials: [dashMat])
        dash.position = SIMD3<Float>(0.0, -0.44, -1.15)
        interior.addChild(dash)

        // Glowing amber/cyan holo-strip on top of the coaming
        let stripMesh = MeshResource.generateBox(size: SIMD3<Float>(0.90, 0.012, 0.025))
        let amberStrip = ModelEntity(mesh: stripMesh, materials: [holoAmber])
        amberStrip.position = SIMD3<Float>(0.0, -0.31, -0.92)
        interior.addChild(amberStrip)

        let sideStripMesh = MeshResource.generateBox(size: SIMD3<Float>(0.28, 0.010, 0.02))
        let leftCyanStrip = ModelEntity(mesh: sideStripMesh, materials: [holoCyan])
        leftCyanStrip.position = SIMD3<Float>(-0.56, -0.31, -0.96)
        leftCyanStrip.orientation = simd_quatf(angle: 0.25, axis: SIMD3<Float>(0, 1, 0))
        interior.addChild(leftCyanStrip)

        let rightCyanStrip = ModelEntity(mesh: sideStripMesh, materials: [holoCyan])
        rightCyanStrip.position = SIMD3<Float>(0.56, -0.31, -0.96)
        rightCyanStrip.orientation = simd_quatf(angle: -0.25, axis: SIMD3<Float>(0, 1, 0))
        interior.addChild(rightCyanStrip)

        // Left & right angled canopy A-pillars
        let pillarMesh = MeshResource.generateBox(size: SIMD3<Float>(0.045, 0.95, 0.055), cornerRadius: 0.01)
        let leftPillar = ModelEntity(mesh: pillarMesh, materials: [strutMat])
        leftPillar.position = SIMD3<Float>(-0.68, 0.05, -1.05)
        let leftTiltZ = simd_quatf(angle: -0.28, axis: SIMD3<Float>(0, 0, 1))
        let leftTiltX = simd_quatf(angle: 0.42, axis: SIMD3<Float>(1, 0, 0))
        leftPillar.orientation = simd_mul(leftTiltZ, leftTiltX)
        interior.addChild(leftPillar)

        let rightPillar = ModelEntity(mesh: pillarMesh, materials: [strutMat])
        rightPillar.position = SIMD3<Float>(0.68, 0.05, -1.05)
        let rightTiltZ = simd_quatf(angle: 0.28, axis: SIMD3<Float>(0, 0, 1))
        let rightTiltX = simd_quatf(angle: 0.42, axis: SIMD3<Float>(1, 0, 0))
        rightPillar.orientation = simd_mul(rightTiltZ, rightTiltX)
        interior.addChild(rightPillar)

        // Upper canopy header bow
        let headerMesh = MeshResource.generateBox(size: SIMD3<Float>(1.18, 0.04, 0.05), cornerRadius: 0.01)
        let header = ModelEntity(mesh: headerMesh, materials: [strutMat])
        header.position = SIMD3<Float>(0.0, 0.46, -0.88)
        interior.addChild(header)

        return interior
    }

    /// Builds a sharp, faceted wedge-delta hull mesh with per-face flat normals.
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
            // Upper forward nose facets
            (nose, leftWingTip, topSpineFwd),
            (nose, topSpineFwd, rightWingTip),
            // Upper main delta wings
            (topSpineFwd, leftWingTip, leftRear),
            (topSpineFwd, leftRear, topSpineAft),
            (topSpineFwd, topSpineAft, rightRear),
            (topSpineFwd, rightRear, rightWingTip),
            // Lower belly facets
            (nose, bellyFwd, leftWingTip),
            (nose, rightWingTip, bellyFwd),
            (bellyFwd, bellyAft, leftWingTip),
            (bellyAft, leftRear, leftWingTip),
            (bellyFwd, rightWingTip, bellyAft),
            (bellyAft, rightWingTip, rightRear),
            // Rear transom
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
            // Both windings so no facet ever culls
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 1])
        }

        var descriptor = MeshDescriptor(name: "KestrelDeltaHull")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)

        return try? MeshResource.generate(from: [descriptor])
    }
}
