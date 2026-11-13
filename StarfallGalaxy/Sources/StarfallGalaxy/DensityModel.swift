import Foundation

/// A breakdown of what makes up the galaxy at one point. Used for star counts,
/// for choosing which kinds of stars appear, and for drawing the galaxy map.
public struct DensityComponents: Sendable {
    /// Young thin disk (where spiral arms live).
    public var thinDisk: Double
    /// Older, puffier thick disk.
    public var thickDisk: Double
    /// Central bar and bulge, plus the dense nucleus.
    public var bulge: Double
    /// Sparse stellar halo.
    public var halo: Double
    /// 0...1, how close this point is to the crest of a spiral arm.
    public var arm: Double
    /// 0...1, dust lane strength (on the inner edge of arms).
    public var dust: Double
    /// 0...1, local star-cloud clumpiness (high values are dense clouds and nebulae).
    public var clump: Double

    /// Total star systems per cubic light-year.
    public var total: Double { thinDisk + thickDisk + bulge + halo }
}

/// A Milky Way model: exponential thin and thick disks, a tilted bar and bulge,
/// four logarithmic spiral arms plus a local spur through Sol, a halo, and noise
/// that makes the star field clumpy.
///
/// Calibrated so the density at Sol is about 0.0033 systems per cubic light-year,
/// which matches the observed solar neighbourhood (roughly 110 systems within 20 ly).
public struct DensityModel: Sendable {
    public let seed: UInt64

    // Shape parameters, in light-years.
    public let solarRadius = 26_670.0        // Sol's distance from the galactic centre
    public let thinScaleLength = 8_500.0
    public let thinScaleHeight = 980.0
    public let thickScaleLength = 11_500.0
    public let thickScaleHeight = 2_900.0
    public let discEdge = 48_000.0
    public let armCount = 4
    public let armPitchDegrees = 13.0
    public let armWidth = 2_100.0
    public let barAngleDegrees = 27.0

    /// Target local density at Sol, in systems per cubic light-year.
    public let localDensity = 0.0033

    private var normalisation: Double

    public init(seed: UInt64) {
        self.seed = seed
        normalisation = 1
        let raw = rawComponents(at: .sol).total
        normalisation = localDensity / raw
    }

    /// Star systems per cubic light-year at a point.
    public func systemsPerCubicLY(at p: GalacticPosition) -> Double {
        components(at: p).total
    }

    public func components(at p: GalacticPosition) -> DensityComponents {
        var c = rawComponents(at: p)
        c.thinDisk *= normalisation
        c.thickDisk *= normalisation
        c.bulge *= normalisation
        c.halo *= normalisation
        return c
    }

    /// Height of the galactic mid-plane at a given z. Sol sits ~68 ly above the plane,
    /// and the plane passes through Sagittarius A*.
    func midplaneY(atZ z: Double) -> Double {
        let centre = GalacticPosition.galacticCentre
        let t = z / centre.z
        return -68 + (centre.y + 68) * t
    }

    private func rawComponents(at p: GalacticPosition) -> DensityComponents {
        let centre = GalacticPosition.galacticCentre
        let a = p.x - centre.x
        let b = p.z - centre.z
        let h = p.y - midplaneY(atZ: p.z)
        let rPlane = (a * a + b * b).squareRoot()
        let r3 = (rPlane * rPlane + h * h).squareRoot()

        // Inner hole (the bar clears out the inner disk) and outer edge.
        let hole = 1 - exp(-pow(rPlane / 9_000, 2))
        let edge = rPlane > discEdge ? exp(-(rPlane - discEdge) / 2_000) : 1

        // Spiral structure.
        let (arm, dust) = armStructure(a: a, b: b, rPlane: rPlane)
        let armFactor = 0.78 + 0.75 * arm

        // Clumpy star clouds.
        let clump = ValueNoise.fbm(seed ^ 0xC10D, p.x / 1_800, p.y / 1_800, p.z / 1_800)
        let clumpFactor = 0.55 + 0.9 * clump

        let thin = exp(-(rPlane - solarRadius) / thinScaleLength)
            * exp(-abs(h) / thinScaleHeight) * hole * edge * armFactor * clumpFactor
        let thick = 0.08 * exp(-(rPlane - solarRadius) / thickScaleLength)
            * exp(-abs(h) / thickScaleHeight) * hole * edge * (0.8 + 0.4 * clump)

        // Bar, rotated relative to the Sol-centre line, plus nucleus.
        let beta = barAngleDegrees * .pi / 180
        let u = -b * cos(beta) + a * sin(beta)
        let v = a * cos(beta) + b * sin(beta)
        let barShape = ((u / 7_000) * (u / 7_000) + (v / 2_600) * (v / 2_600) + (h / 1_400) * (h / 1_400)).squareRoot()
        let bulge = 18 * exp(-barShape) + 180 * exp(-r3 / 250)

        let halo = 0.0015 * pow(solarRadius / max(r3, 3_000), 3)

        return DensityComponents(thinDisk: thin, thickDisk: thick, bulge: bulge, halo: halo, arm: arm, dust: dust, clump: clump)
    }

    /// Returns arm strength (0...1) and dust strength (0...1) for a point in the disk plane.
    private func armStructure(a: Double, b: Double, rPlane: Double) -> (Double, Double) {
        guard rPlane > 1 else { return (0, 0) }
        let theta = atan2(a, -b)                       // Sol sits near theta = 0
        let pitch = armPitchDegrees * .pi / 180
        let winding = log(rPlane / solarRadius) / tan(pitch)
        let spacing = 2 * Double.pi / Double(armCount)

        // Distance to the nearest of the four arms. Phase puts Sol between arms.
        let phase = theta + winding - spacing / 2
        var offset = phase.truncatingRemainder(dividingBy: spacing)
        if offset > spacing / 2 { offset -= spacing }
        if offset < -spacing / 2 { offset += spacing }
        let across = rPlane * offset * sin(pitch)      // signed distance across the arm

        // Two major arms (like Scutum-Centaurus and Perseus) and two weaker ones.
        let armIndex = ((Int(((phase - offset) / spacing).rounded()) % armCount) + armCount) % armCount
        let strength = armIndex % 2 == 0 ? 1.0 : 0.55
        let width = armWidth * (armIndex % 2 == 0 ? 1.0 : 0.8)

        // Arms are patchy: bright star clouds and gaps along their length.
        let patch = ValueNoise.fbm(seed ^ 0xA2A5, a / 4_500, 0, b / 4_500, octaves: 3)
        var arm = strength * exp(-0.5 * pow(across / width, 2)) * (0.35 + 1.3 * patch)
        arm = min(1, arm)

        // The local (Orion) spur through Sol: weaker and shorter.
        var spurOffset = (theta + winding).truncatingRemainder(dividingBy: 2 * .pi)
        if spurOffset > .pi { spurOffset -= 2 * .pi }
        if spurOffset < -.pi { spurOffset += 2 * .pi }
        let spurAcross = rPlane * spurOffset * sin(pitch)
        let spur = 0.55 * exp(-0.5 * pow(spurAcross / 1_000, 2)) * exp(-0.5 * pow((rPlane - solarRadius) / 3_500, 2))
        arm = max(arm, spur)

        // Arms fade out inside the bar region.
        let inner = min(1, max(0, (rPlane - 9_000) / 5_000))
        let smoothInner = inner * inner * (3 - 2 * inner)
        arm *= smoothInner

        // Dust lanes hug the inner edge of each arm, broken up like the real thing.
        let dustPatch = ValueNoise.fbm(seed ^ 0xD057, a / 2_500, 0, b / 2_500, octaves: 3)
        let dust = strength * exp(-0.5 * pow((across + width * 0.6) / (width * 0.4), 2))
            * smoothInner * max(0, dustPatch * 1.8 - 0.35)
        return (arm, min(1, dust))
    }

    /// Estimates the total number of star systems by integrating the model on a grid.
    /// Slow (a few seconds); meant for tools and tests, not gameplay.
    public func estimatedTotalSystems(step: Double = 500, verticalStep: Double = 100) -> Double {
        let centre = GalacticPosition.galacticCentre
        var total = 0.0
        let half = 60_000.0
        var x = -half
        while x < half {
            var z = -half
            while z < half {
                let r = (x * x + z * z).squareRoot()
                if r < 58_000 {
                    var y = -6_000.0
                    while y < 6_000 {
                        let p = GalacticPosition(x: centre.x + x + step / 2, y: centre.y + y + verticalStep / 2, z: centre.z + z + step / 2)
                        total += systemsPerCubicLY(at: p)
                        y += verticalStep
                    }
                }
                z += step
            }
            x += step
        }
        return total * step * step * verticalStep
    }
}
