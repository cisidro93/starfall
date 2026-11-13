import Foundation

public enum StellarClass: String, Codable, Sendable, CaseIterable {
    case O, B, A, F, G, K, M
    case L, T, Y                      // brown dwarfs
    case whiteDwarf = "D"
    case neutronStar = "N"
    case blackHole = "BH"

    public var isMainSequenceKind: Bool {
        switch self {
        case .O, .B, .A, .F, .G, .K, .M: return true
        default: return false
        }
    }

    public var isBrownDwarf: Bool { self == .L || self == .T || self == .Y }
    public var isRemnant: Bool { self == .whiteDwarf || self == .neutronStar || self == .blackHole }

    /// Plain-language name for the UI.
    public var displayName: String {
        switch self {
        case .O: return "Blue giant (O)"
        case .B: return "Blue-white star (B)"
        case .A: return "White star (A)"
        case .F: return "Yellow-white star (F)"
        case .G: return "Yellow star (G)"
        case .K: return "Orange star (K)"
        case .M: return "Red dwarf (M)"
        case .L, .T, .Y: return "Brown dwarf (\(rawValue))"
        case .whiteDwarf: return "White dwarf"
        case .neutronStar: return "Neutron star"
        case .blackHole: return "Black hole"
        }
    }
}

public enum LuminosityClass: String, Codable, Sendable {
    case supergiant = "I"
    case brightGiant = "II"
    case giant = "III"
    case subgiant = "IV"
    case mainSequence = "V"
    case none = ""
}

public struct RGB: Codable, Sendable, Hashable {
    public var r: Double, g: Double, b: Double
}

public struct Star: Codable, Sendable, Hashable {
    public var name: String
    public var stellarClass: StellarClass
    /// 0 (hottest) to 9 (coolest) within the class.
    public var subclass: Double
    public var luminosityClass: LuminosityClass
    public var massSolar: Double
    public var radiusSolar: Double
    public var temperatureK: Double
    public var luminositySolar: Double
    /// Separation from the primary star; 0 for the primary.
    public var separationAU: Double

    public var spectralType: String {
        switch stellarClass {
        case .whiteDwarf: return "DA"
        case .neutronStar: return "Neutron"
        case .blackHole: return "Black hole"
        default:
            let sub = subclass == subclass.rounded() ? String(Int(subclass)) : String(format: "%.1f", subclass)
            return "\(stellarClass.rawValue)\(sub)\(luminosityClass.rawValue)"
        }
    }

    /// Approximate visible colour of a black body at this temperature (0...1 channels).
    public var color: RGB {
        if stellarClass == .blackHole { return RGB(r: 0.05, g: 0.05, b: 0.08) }
        return Star.blackbodyColor(temperatureK)
    }

    static func blackbodyColor(_ kelvin: Double) -> RGB {
        let t = min(40_000, max(1_000, kelvin)) / 100
        var r: Double, g: Double, b: Double
        if t <= 66 {
            r = 255
            g = 99.4708025861 * log(t) - 161.1195681661
            b = t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307
        } else {
            r = 329.698727446 * pow(t - 60, -0.1332047592)
            g = 288.1221695283 * pow(t - 60, -0.0755148492)
            b = 255
        }
        func c(_ v: Double) -> Double { min(1, max(0, v / 255)) }
        return RGB(r: c(r), g: c(g), b: c(b))
    }

    /// Builds a physically consistent star from its class. Luminosity follows from
    /// radius and temperature (L = R^2 * (T / 5772)^4).
    static func make(name: String, cls: StellarClass, subclass: Double, lum: LuminosityClass,
                     separationAU: Double, rng: inout SplitMix64) -> Star {
        let t = subclass / 9.5   // 0 hot ... ~1 cool
        func logLerp(_ hot: Double, _ cool: Double) -> Double { hot * pow(cool / hot, t) }
        var mass: Double, radius: Double, temp: Double
        switch cls {
        case .O: temp = logLerp(50_000, 30_000); mass = logLerp(60, 16); radius = logLerp(15, 6.6)
        case .B: temp = logLerp(30_000, 10_000); mass = logLerp(16, 2.1); radius = logLerp(6.6, 1.8)
        case .A: temp = logLerp(10_000, 7_500); mass = logLerp(2.1, 1.4); radius = logLerp(1.8, 1.4)
        case .F: temp = logLerp(7_500, 6_000); mass = logLerp(1.4, 1.04); radius = logLerp(1.4, 1.15)
        case .G: temp = logLerp(6_000, 5_200); mass = logLerp(1.04, 0.8); radius = logLerp(1.15, 0.86)
        case .K: temp = logLerp(5_200, 3_700); mass = logLerp(0.8, 0.45); radius = logLerp(0.86, 0.63)
        case .M: temp = logLerp(3_700, 2_400); mass = logLerp(0.45, 0.08); radius = logLerp(0.63, 0.1)
        case .L: temp = logLerp(2_400, 1_300); mass = logLerp(0.08, 0.06); radius = 0.1
        case .T: temp = logLerp(1_300, 600); mass = logLerp(0.06, 0.03); radius = 0.095
        case .Y: temp = logLerp(600, 300); mass = logLerp(0.03, 0.01); radius = 0.09
        case .whiteDwarf:
            temp = rng.logUniform(4_500, 30_000); mass = rng.uniform(0.5, 1.0); radius = 0.0127 / pow(mass / 0.6, 1.0 / 3)
        case .neutronStar:
            temp = rng.logUniform(1e5, 1e6); mass = rng.uniform(1.3, 2.1); radius = 1.6e-5
        case .blackHole:
            temp = 0; mass = rng.logUniform(5, 25); radius = 4.24e-6 * mass
        }
        switch lum {
        case .giant:
            radius *= cls == .G ? rng.uniform(6, 12) : rng.uniform(15, 60)
            mass = max(mass, rng.uniform(1.0, 3.0))
            temp *= 0.92
        case .brightGiant:
            radius *= rng.uniform(25, 80); mass = max(mass, rng.uniform(3, 8))
        case .supergiant:
            radius *= cls == .M ? rng.uniform(400, 900) : rng.uniform(20, 60)
            mass = max(mass, rng.uniform(10, 25))
        case .subgiant:
            radius *= rng.uniform(1.5, 2.5)
        default:
            break
        }
        let luminosity: Double
        switch cls {
        case .blackHole: luminosity = 0
        case .neutronStar: luminosity = 1e-5
        default: luminosity = radius * radius * pow(temp / 5_772, 4)
        }
        return Star(name: name, stellarClass: cls, subclass: subclass, luminosityClass: lum,
                    massSolar: mass, radiusSolar: radius, temperatureK: temp,
                    luminositySolar: luminosity, separationAU: separationAU)
    }
}

/// The local mix of stellar populations, which shifts which kinds of stars appear.
struct StellarEnvironment {
    /// 0...1 crest of a spiral arm (more young, hot stars).
    var arm: Double
    /// 0...1 share of old populations (bulge, thick disk, halo).
    var oldFraction: Double

    init(_ c: DensityComponents) {
        arm = c.arm
        let total = max(c.total, 1e-30)
        oldFraction = min(1, (c.bulge + c.thickDisk + c.halo) / total)
    }

    init(arm: Double, oldFraction: Double) {
        self.arm = arm
        self.oldFraction = oldFraction
    }
}

enum StarFactory {
    static let classes: [StellarClass] = [.O, .B, .A, .F, .G, .K, .M, .L, .T, .Y, .whiteDwarf, .neutronStar, .blackHole]

    /// Relative frequencies of system primaries in the solar neighbourhood.
    /// Remnants and hot stars are kept rare so they stay worth finding: within 100 ly of Sol
    /// expect a dozen or so B stars, a few neutron stars, and usually no black holes.
    static let baseWeights: [Double] = [0.00002, 0.04, 0.6, 3.0, 7.6, 12.1, 63.0, 2.0, 3.0, 1.0, 6.0, 0.02, 0.002]

    static func primaryClass(_ env: StellarEnvironment, rng: inout SplitMix64) -> (StellarClass, LuminosityClass) {
        let young = env.arm * (1 - env.oldFraction)
        var w = baseWeights
        w[0] *= 1 + 9 * young          // O
        w[1] *= 1 + 3 * young          // B
        w[2] *= 1 + 0.8 * young        // A
        w[0] *= 1 - 0.95 * env.oldFraction
        w[1] *= 1 - 0.8 * env.oldFraction
        w[2] *= 1 - 0.5 * env.oldFraction
        w[10] *= 1 + 1.5 * env.oldFraction  // more white dwarfs in old regions
        let cls = classes[rng.weightedIndex(w)]

        // Luminosity class: mostly main sequence; giants more common where stars are old.
        var lum: LuminosityClass = cls.isMainSequenceKind ? .mainSequence : .none
        if cls.isMainSequenceKind {
            let roll = rng.unit()
            switch cls {
            case .G, .K, .M:
                let giantChance = 0.012 + 0.08 * env.oldFraction
                if roll < giantChance * 0.04 && cls != .G { lum = .supergiant }
                else if roll < giantChance { lum = .giant }
                else if roll < giantChance + 0.02 && cls != .M { lum = .subgiant }
            case .O, .B, .A:
                if roll < 0.04 { lum = .supergiant }
                else if roll < 0.08 { lum = .brightGiant }
                else if roll < 0.18 { lum = .giant }
                else if roll < 0.3 { lum = .subgiant }
            case .F:
                if roll < 0.08 { lum = .subgiant }
            default: break
            }
        }
        return (cls, lum)
    }

    static func companionChance(_ cls: StellarClass) -> Double {
        switch cls {
        case .O, .B: return 0.6
        case .A: return 0.5
        case .F, .G: return 0.45
        case .K: return 0.35
        case .M: return 0.25
        case .whiteDwarf: return 0.25
        case .L, .T, .Y: return 0.15
        case .neutronStar, .blackHole: return 0.3
        }
    }

    /// Companions are drawn the same way, but never hotter than the primary.
    static func companionClass(primary: StellarClass, rng: inout SplitMix64) -> StellarClass {
        let order: [StellarClass] = [.O, .B, .A, .F, .G, .K, .M, .L, .T]
        let start = order.firstIndex(of: primary) ?? 5
        let candidates = Array(order[start...])
        if candidates.isEmpty { return .M }
        var w = candidates.map { c -> Double in
            switch c {
            case .M: return 6
            case .K: return 2
            case .G: return 1.2
            case .L, .T: return 0.8
            default: return 0.5
            }
        }
        if rng.chance(0.08) { return .whiteDwarf }
        w[0] += 0.5  // twins are common
        return candidates[rng.weightedIndex(w)]
    }
}
