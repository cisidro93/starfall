import Foundation

/// A position in the galaxy, in light-years, with Sol at the origin.
///
/// Axes (a cyclic permutation of IAU galactic coordinates, so the frame stays right-handed):
/// - `+z` points toward the galactic centre (galactic longitude 0°)
/// - `+x` points along galactic longitude 90° (the direction of galactic rotation)
/// - `+y` points toward the north galactic pole
public struct GalacticPosition: Hashable, Codable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// Sol, the origin of the frame.
    public static let sol = GalacticPosition(x: 0, y: 0, z: 0)

    /// Sagittarius A*, approx. 26,670 ly away at l = 359.944°, b = -0.046°.
    public static let galacticCentre = GalacticPosition(x: -26, y: -21, z: 26_670)

    public func distance(to other: GalacticPosition) -> Double {
        let dx = x - other.x, dy = y - other.y, dz = z - other.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    public func distanceSquared(to other: GalacticPosition) -> Double {
        let dx = x - other.x, dy = y - other.y, dz = z - other.z
        return dx * dx + dy * dy + dz * dz
    }

    public static func + (a: GalacticPosition, b: GalacticPosition) -> GalacticPosition {
        GalacticPosition(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z)
    }

    public static func - (a: GalacticPosition, b: GalacticPosition) -> GalacticPosition {
        GalacticPosition(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)
    }

    public var description: String {
        String(format: "(%.2f, %.2f, %.2f) ly", x, y, z)
    }

    /// Converts J2000 equatorial coordinates and a distance into a galactic position.
    /// - Parameters:
    ///   - rightAscensionHours: right ascension in decimal hours
    ///   - declinationDegrees: declination in decimal degrees
    ///   - distanceLY: distance from Sol in light-years
    public init(rightAscensionHours: Double, declinationDegrees: Double, distanceLY: Double) {
        let ra = rightAscensionHours * 15.0 * .pi / 180.0
        let dec = declinationDegrees * .pi / 180.0
        let ex = cos(dec) * cos(ra)
        let ey = cos(dec) * sin(ra)
        let ez = sin(dec)
        // ICRS -> galactic rotation matrix (Hipparcos, J2000).
        let gx = -0.0548755604 * ex - 0.8734370902 * ey - 0.4838350155 * ez
        let gy = 0.4941094279 * ex - 0.4448296300 * ey + 0.7469822445 * ez
        let gz = -0.8676661490 * ex - 0.1980763734 * ey + 0.4559837762 * ez
        // Map galactic (toward centre, toward l=90°, toward NGP) into the game frame.
        self.init(x: gy * distanceLY, y: gz * distanceLY, z: gx * distanceLY)
    }
}

/// A 10-light-year cube of space. Stars are generated per cell, on demand.
public struct CellCoordinate: Hashable, Codable, Sendable {
    public static let size: Double = 10

    public var x: Int32
    public var y: Int32
    public var z: Int32

    public init(x: Int32, y: Int32, z: Int32) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(containing p: GalacticPosition) {
        self.init(x: Int32((p.x / Self.size).rounded(.down)),
                  y: Int32((p.y / Self.size).rounded(.down)),
                  z: Int32((p.z / Self.size).rounded(.down)))
    }

    public var origin: GalacticPosition {
        GalacticPosition(x: Double(x) * Self.size, y: Double(y) * Self.size, z: Double(z) * Self.size)
    }

    public var centre: GalacticPosition {
        let h = Self.size / 2
        return GalacticPosition(x: Double(x) * Self.size + h, y: Double(y) * Self.size + h, z: Double(z) * Self.size + h)
    }

    /// Smallest squared distance from a point to any point in this cell.
    func minimumDistanceSquared(to p: GalacticPosition) -> Double {
        let o = origin
        func axis(_ v: Double, _ lo: Double) -> Double {
            let hi = lo + Self.size
            if v < lo { return lo - v }
            if v > hi { return v - hi }
            return 0
        }
        let dx = axis(p.x, o.x), dy = axis(p.y, o.y), dz = axis(p.z, o.z)
        return dx * dx + dy * dy + dz * dz
    }
}
