import Foundation
import RealityKit
import simd
import StarfallGalaxy

/// Stores an entity's true double-precision world position in metres.
struct WorldPositionComponent: Component, Sendable {
    var position: SIMD3<Double>

    init(_ position: SIMD3<Double>) {
        self.position = position
    }

    init(x: Double, y: Double, z: Double) {
        self.position = SIMD3<Double>(x, y, z)
    }
}

/// Marks a distant planetary or stellar body whose true `SIMD3<Double>` position and radius
/// are projected onto a camera-relative shell (`proxyDistance`) so its apparent angular size
/// and direction are physically exact without clipping the camera's far plane.
struct PlanetaryBodyComponent: Component, Sendable {
    var bodyName: String
    var worldPosition: SIMD3<Double>
    var trueRadiusMetres: Double
    var proxyDistanceMetres: Float
}
