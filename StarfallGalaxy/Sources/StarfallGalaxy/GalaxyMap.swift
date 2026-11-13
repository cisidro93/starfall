import Foundation

/// An RGB image of the galaxy seen from above the north galactic pole.
public struct GalaxyImage: Sendable {
    public var width: Int
    public var height: Int
    /// Row-major RGB bytes, top row first.
    public var pixels: [UInt8]
    /// Light-years covered by the image, edge to edge.
    public var extentLY: Double
    /// Galactic position at the centre of the image.
    public var centre: GalacticPosition

    /// Converts a galactic position to pixel coordinates (top-left origin).
    /// The galactic centre is "up" from Sol, as on most Milky Way maps.
    public func pixel(for p: GalacticPosition) -> (x: Double, y: Double) {
        let scale = Double(width) / extentLY
        return (Double(width) / 2 + (p.x - centre.x) * scale,
                Double(height) / 2 - (p.z - centre.z) * scale)
    }

    /// Binary PPM (P6) data, readable by most image tools.
    public func ppmData() -> Data {
        var d = Data("P6\n\(width) \(height)\n255\n".utf8)
        d.append(contentsOf: pixels)
        return d
    }
}

public enum GalaxyMapRenderer {
    /// Renders a top-down view by integrating light and dust through the disk.
    /// - Parameters:
    ///   - size: output width and height in pixels
    ///   - extentLY: width of the view in light-years (110,000 shows the whole galaxy)
    ///   - centre: what the image is centred on (defaults to the galactic centre)
    ///   - verticalSamples: samples through the disk per pixel (more is smoother, slower)
    public static func render(_ galaxy: Galaxy, size: Int = 1024, extentLY: Double = 110_000,
                              centre: GalacticPosition = .galacticCentre, verticalSamples: Int = 28) -> GalaxyImage {
        let model = galaxy.density
        var light = [Double](repeating: 0, count: size * size * 3)
        var youngLight = [Double](repeating: 0, count: size * size)
        let scale = extentLY / Double(size)
        let halfDepth = 4_000.0
        let dy = 2 * halfDepth / Double(verticalSamples)

        for py in 0..<size {
            for px in 0..<size {
                let x = centre.x + (Double(px) + 0.5 - Double(size) / 2) * scale
                let z = centre.z - (Double(py) + 0.5 - Double(size) / 2) * scale
                var r = 0.0, g = 0.0, b = 0.0, youngSum = 0.0
                var transmission = 1.0
                // March from above the disk downward, so dust dims the light behind it.
                var y = centre.y + halfDepth - dy / 2
                for _ in 0..<verticalSamples {
                    let c = model.components(at: GalacticPosition(x: x, y: y, z: z))
                    // Young arm stars are blue-white; the old disk is warm; the bulge is golden.
                    let young = c.thinDisk * (0.25 + 2.2 * c.arm * c.arm)
                    let old = c.thinDisk * 0.55 + c.thickDisk + c.halo
                    let bulge = c.bulge
                    // Star-forming nebulae (pink) where dense clouds sit on arm crests.
                    let nebula = c.thinDisk * c.arm * c.arm * max(0, c.clump - 0.58) * 26
                    r += transmission * (young * 0.60 + old * 1.0 + bulge * 1.0 + nebula * 1.0) * dy
                    g += transmission * (young * 0.75 + old * 0.80 + bulge * 0.70 + nebula * 0.38) * dy
                    b += transmission * (young * 1.00 + old * 0.58 + bulge * 0.40 + nebula * 0.60) * dy
                    youngSum += transmission * young * dy
                    let dustDensity = c.dust * c.thinDisk * 0.022 + c.thinDisk * 0.00004
                    transmission *= exp(-dustDensity * dy * 12)
                    y -= dy
                }
                let i = (py * size + px) * 3
                light[i] = r
                light[i + 1] = g
                light[i + 2] = b
                youngLight[py * size + px] = youngSum
            }
        }

        // Tone map: logarithmic, normalised to a high percentile so the core doesn't blow out.
        var luminance = [Double]()
        luminance.reserveCapacity(size * size)
        for i in stride(from: 0, to: light.count, by: 3) {
            let sum: Double = light[i] + light[i + 1] + light[i + 2]
            luminance.append(sum)
        }
        let sorted = luminance.sorted()
        let reference = max(sorted[Int(Double(sorted.count - 1) * 0.997)], 1e-12)
        let k = 60.0 / reference
        var mapped = [Double](repeating: 0, count: light.count)
        for i in 0..<light.count {
            let v = log(1 + k * light[i]) / log(1 + 60.0 * 1.15)
            mapped[i] = pow(min(1, max(0, v)), 1.15)
        }

        // Resolved bright stars: a deterministic sprinkle, densest where young stars are.
        let youngReference = max(youngLight.sorted()[Int(Double(youngLight.count - 1) * 0.99)], 1e-12)
        for p in 0..<(size * size) {
            let h = SplitMix64.hash(galaxy.seed, 0x5BA4C1E, UInt64(p))
            let u = Double(h >> 11) * 0x1.0p-53
            let chance = min(0.1, 0.09 * youngLight[p] / youngReference) + 0.003
            guard u < chance else { continue }
            let tint = Double((h >> 3) & 0xFF) / 255          // blue-white to warm
            let boost = 0.12 + 0.6 * pow(Double((h >> 13) & 0xFF) / 255, 2)
            let i = p * 3
            mapped[i] = min(1, mapped[i] + boost * (0.75 + 0.25 * tint))
            mapped[i + 1] = min(1, mapped[i + 1] + boost * 0.85)
            mapped[i + 2] = min(1, mapped[i + 2] + boost * (1.0 - 0.3 * tint))
        }

        var pixels = [UInt8](repeating: 0, count: light.count)
        for i in 0..<light.count {
            pixels[i] = UInt8((mapped[i] * 255).rounded())
        }
        return GalaxyImage(width: size, height: size, pixels: pixels, extentLY: extentLY, centre: centre)
    }
}
