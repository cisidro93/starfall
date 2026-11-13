import Foundation

/// SplitMix64: a small, fast, fully specified generator.
///
/// Everything in the galaxy is derived from this, so the same seed always produces
/// the same galaxy. Swift's own `random(in:using:)` algorithms are not guaranteed to stay
/// the same across Swift versions, so this file provides its own helpers instead.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        return Self.mix(state)
    }

    /// The SplitMix64 finaliser: turns any 64-bit value into a well-scrambled one.
    public static func mix(_ value: UInt64) -> UInt64 {
        var z = value
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Combines several values into one well-mixed hash. Order matters.
    public static func hash(_ values: UInt64...) -> UInt64 {
        var h: UInt64 = 0x51A7_FA11_D41F_7000
        for v in values {
            h = mix(h ^ mix(v &+ 0x9E37_79B9_7F4A_7C15))
        }
        return h
    }

    /// Uniform double in [0, 1).
    public mutating func unit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    public mutating func uniform(_ lo: Double, _ hi: Double) -> Double {
        lo + (hi - lo) * unit()
    }

    /// Log-uniform value between two positive bounds.
    public mutating func logUniform(_ lo: Double, _ hi: Double) -> Double {
        lo * pow(hi / lo, unit())
    }

    public mutating func chance(_ probability: Double) -> Bool {
        unit() < probability
    }

    /// Uniform integer in the closed range.
    public mutating func int(_ range: ClosedRange<Int>) -> Int {
        let span = range.upperBound - range.lowerBound + 1
        return range.lowerBound + min(span - 1, Int(unit() * Double(span)))
    }

    /// Picks an index according to the given (unnormalised) weights.
    public mutating func weightedIndex(_ weights: [Double]) -> Int {
        let total = weights.reduce(0, +)
        var r = unit() * total
        for (i, w) in weights.enumerated() {
            if r < w { return i }
            r -= w
        }
        return weights.count - 1
    }

    /// Binomial draw that approximates Poisson(lambda) using only basic arithmetic,
    /// so star counts never depend on platform maths libraries.
    public mutating func starCount(expected lambda: Double) -> Int {
        guard lambda > 0 else { return 0 }
        let trials = 2 * Int(lambda.rounded(.up)) + 16
        let p = lambda / Double(trials)
        var count = 0
        for _ in 0..<trials where unit() < p {
            count += 1
        }
        return count
    }
}

/// Deterministic 3D value noise, used to make star fields clumpy instead of uniform.
enum ValueNoise {
    static func lattice(_ seed: UInt64, _ x: Int64, _ y: Int64, _ z: Int64) -> Double {
        let h = SplitMix64.hash(seed, UInt64(bitPattern: x), UInt64(bitPattern: y), UInt64(bitPattern: z))
        return Double(h >> 11) * 0x1.0p-53
    }

    static func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    static func noise(_ seed: UInt64, _ x: Double, _ y: Double, _ z: Double) -> Double {
        let fx = x.rounded(.down), fy = y.rounded(.down), fz = z.rounded(.down)
        let ix = Int64(fx), iy = Int64(fy), iz = Int64(fz)
        let tx = smooth(x - fx), ty = smooth(y - fy), tz = smooth(z - fz)
        func l(_ a: Int64, _ b: Int64, _ c: Int64) -> Double { lattice(seed, ix + a, iy + b, iz + c) }
        let x00 = l(0, 0, 0) + (l(1, 0, 0) - l(0, 0, 0)) * tx
        let x10 = l(0, 1, 0) + (l(1, 1, 0) - l(0, 1, 0)) * tx
        let x01 = l(0, 0, 1) + (l(1, 0, 1) - l(0, 0, 1)) * tx
        let x11 = l(0, 1, 1) + (l(1, 1, 1) - l(0, 1, 1)) * tx
        let y0 = x00 + (x10 - x00) * ty
        let y1 = x01 + (x11 - x01) * ty
        return y0 + (y1 - y0) * tz
    }

    /// Fractal noise in [0, 1].
    static func fbm(_ seed: UInt64, _ x: Double, _ y: Double, _ z: Double, octaves: Int = 4) -> Double {
        var sum = 0.0, amp = 0.5, freq = 1.0, norm = 0.0
        for o in 0..<octaves {
            sum += amp * noise(seed &+ UInt64(o), x * freq, y * freq, z * freq)
            norm += amp
            amp *= 0.5
            freq *= 2.03
        }
        return sum / norm
    }
}
