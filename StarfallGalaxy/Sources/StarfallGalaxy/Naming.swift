import Foundation

/// Procedural names. The galaxy is split into 2,000 ly naming regions, each with a
/// pronounceable name; systems inside get a unique catalogue designation, like
/// "Velmira KD-18234 2".
enum Naming {
    static let regionSize = 2_000.0
    static let cellsPerRegion = Int32(regionSize / CellCoordinate.size)  // 200

    static let onsets = ["", "b", "c", "d", "f", "g", "h", "k", "l", "m", "n", "p", "r", "s", "t", "v", "z",
                         "th", "dr", "kr", "st", "tr", "vel", "cal", "mor", "ser", "an", "or", "el"]
    static let vowels = ["a", "e", "i", "o", "u", "ae", "ia", "io", "ei", "y"]
    static let codas = ["", "", "n", "r", "s", "l", "th", "x", "m", "nd", "rn", "ss"]

    /// Shifts the region grid so Sol sits in the middle of a region, not on a corner.
    static func shifted(_ cell: CellCoordinate) -> CellCoordinate {
        let h = cellsPerRegion / 2
        return CellCoordinate(x: cell.x + h, y: cell.y + h, z: cell.z + h)
    }

    static func regionName(seed: UInt64, cell original: CellCoordinate) -> String {
        let cell = shifted(original)
        let rx = floorDiv(cell.x, cellsPerRegion), ry = floorDiv(cell.y, cellsPerRegion), rz = floorDiv(cell.z, cellsPerRegion)
        var rng = SplitMix64(seed: SplitMix64.hash(seed, 0x4E414D45,
                                                   UInt64(bitPattern: Int64(rx)), UInt64(bitPattern: Int64(ry)),
                                                   UInt64(bitPattern: Int64(rz))))
        let syllables = rng.chance(0.6) ? 2 : 3
        var s = ""
        for i in 0..<syllables {
            s += onsets[rng.int(0...(onsets.count - 1))]
            s += vowels[rng.int(0...(vowels.count - 1))]
            if i == syllables - 1 || rng.chance(0.3) { s += codas[rng.int(0...(codas.count - 1))] }
        }
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    static func designation(seed: UInt64, cell original: CellCoordinate, index: Int) -> String {
        let cell = shifted(original)
        let lx = floorMod(cell.x, cellsPerRegion), ly = floorMod(cell.y, cellsPerRegion), lz = floorMod(cell.z, cellsPerRegion)
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let a = letters[Int(lx) / 26 % 26], b = letters[Int(lx) % 26]
        let number = Int(ly) * Int(cellsPerRegion) + Int(lz)
        return "\(regionName(seed: seed, cell: original)) \(a)\(b)-\(number) \(index + 1)"
    }

    static func floorDiv(_ a: Int32, _ b: Int32) -> Int32 {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    static func floorMod(_ a: Int32, _ b: Int32) -> Int32 {
        let m = a % b
        return m < 0 ? m + b : m
    }
}
