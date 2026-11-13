import Foundation

/// One star in a real, catalogued system.
public struct CatalogueStar: Sendable {
    public var suffix: String               // "A", "B", "" for single stars, or a full name
    public var stellarClass: StellarClass
    public var subclass: Double
    public var luminosityClass: LuminosityClass
    public var separationAU: Double
    // Optional measured values that override the class-based estimates.
    public var massSolar: Double?
    public var radiusSolar: Double?
    public var temperatureK: Double?

    public init(_ suffix: String, _ cls: StellarClass, _ subclass: Double, _ lum: LuminosityClass,
                sep: Double = 0, mass: Double? = nil, radius: Double? = nil, temp: Double? = nil) {
        self.suffix = suffix
        stellarClass = cls
        self.subclass = subclass
        luminosityClass = lum
        separationAU = sep
        massSolar = mass
        radiusSolar = radius
        temperatureK = temp
    }
}

/// A confirmed exoplanet, placed exactly; the rest of the system is generated around it.
public struct KnownPlanet: Sendable {
    public var suffix: String
    public var hostStar: Int
    public var semiMajorAxisAU: Double
    public var massEarth: Double

    public init(_ suffix: String, host: Int = 0, au: Double, mass: Double) {
        self.suffix = suffix
        hostStar = host
        semiMajorAxisAU = au
        massEarth = mass
    }
}

/// A real star system with a measured position.
public struct CatalogueEntry: Sendable {
    public var name: String
    public var position: GalacticPosition
    public var stars: [CatalogueStar]
    public var knownPlanets: [KnownPlanet]

    /// - Parameters:
    ///   - ra: right ascension (hours, minutes, seconds), J2000
    ///   - dec: declination (degrees, arcminutes, arcseconds), J2000; the sign goes on degrees
    ///     (this form can't express declinations between 0 and -1 degree; none are needed yet)
    init(_ name: String, ra: (Double, Double, Double), dec: (Double, Double, Double), ly: Double,
         _ stars: [CatalogueStar], planets: [KnownPlanet] = []) {
        let raHours = ra.0 + ra.1 / 60 + ra.2 / 3600
        let sign: Double = dec.0 < 0 ? -1 : 1
        let decDeg = sign * (abs(dec.0) + dec.1 / 60 + dec.2 / 3600)
        self.name = name
        position = GalacticPosition(rightAscensionHours: raHours, declinationDegrees: decDeg, distanceLY: ly)
        self.stars = stars
        knownPlanets = planets
    }

    init(_ name: String, position: GalacticPosition, _ stars: [CatalogueStar], planets: [KnownPlanet] = []) {
        self.name = name
        self.position = position
        self.stars = stars
        knownPlanets = planets
    }
}

/// Real stars. Positions and properties are approximate published values (J2000);
/// they are good to well under a light-year for nearby stars. Replace or extend with a
/// full catalogue import (for example the HYG database, built from Hipparcos and Gaia)
/// before shipping.
public enum StarCatalogue {
    /// Inside this radius the catalogue is treated as complete, so no procedural stars
    /// are generated there.
    public static let completeRadiusLY = 13.5

    public static let entries: [CatalogueEntry] = [
        CatalogueEntry("Sol", position: .sol, [CatalogueStar("", .G, 2, .mainSequence, mass: 1, radius: 1, temp: 5_772)]),

        // Nearest neighbours (within about 13 ly).
        CatalogueEntry("Alpha Centauri", ra: (14, 39, 36.5), dec: (-60, 50, 2), ly: 4.37, [
            CatalogueStar("A", .G, 2, .mainSequence, mass: 1.08, radius: 1.22, temp: 5_790),
            CatalogueStar("B", .K, 1, .mainSequence, sep: 23.4, mass: 0.91, radius: 0.86, temp: 5_260),
            CatalogueStar("Proxima Centauri", .M, 5.5, .mainSequence, sep: 13_000, mass: 0.122, radius: 0.154, temp: 3_042),
        ], planets: [KnownPlanet("d", host: 2, au: 0.0289, mass: 0.26), KnownPlanet("b", host: 2, au: 0.0485, mass: 1.07)]),
        CatalogueEntry("Barnard's Star", ra: (17, 57, 48.5), dec: (4, 41, 36), ly: 5.96,
                       [CatalogueStar("", .M, 4, .mainSequence, mass: 0.16, radius: 0.19, temp: 3_195)],
                       planets: [KnownPlanet("b", au: 0.0188, mass: 0.37)]),
        CatalogueEntry("Wolf 359", ra: (10, 56, 29.2), dec: (7, 0, 53), ly: 7.86,
                       [CatalogueStar("", .M, 6, .mainSequence, mass: 0.11, radius: 0.144, temp: 2_749)]),
        CatalogueEntry("Lalande 21185", ra: (11, 3, 20.2), dec: (35, 58, 12), ly: 8.31,
                       [CatalogueStar("", .M, 2, .mainSequence, mass: 0.39, radius: 0.39, temp: 3_547)],
                       planets: [KnownPlanet("b", au: 0.0788, mass: 2.7)]),
        CatalogueEntry("Sirius", ra: (6, 45, 8.9), dec: (-16, 42, 58), ly: 8.60, [
            CatalogueStar("A", .A, 1, .mainSequence, mass: 2.06, radius: 1.71, temp: 9_940),
            CatalogueStar("B", .whiteDwarf, 2, .none, sep: 19.8, mass: 1.02, radius: 0.0084, temp: 25_000),
        ]),
        CatalogueEntry("Luyten 726-8", ra: (1, 39, 1.3), dec: (-17, 57, 1), ly: 8.73, [
            CatalogueStar("A", .M, 5.5, .mainSequence, mass: 0.10, radius: 0.14, temp: 2_670),
            CatalogueStar("B", .M, 6, .mainSequence, sep: 5.5, mass: 0.10, radius: 0.14, temp: 2_650),
        ]),
        CatalogueEntry("Ross 154", ra: (18, 49, 49.4), dec: (-23, 50, 10), ly: 9.70,
                       [CatalogueStar("", .M, 3.5, .mainSequence, mass: 0.17, radius: 0.24, temp: 3_248)]),
        CatalogueEntry("Ross 248", ra: (23, 41, 55.0), dec: (44, 10, 30), ly: 10.30,
                       [CatalogueStar("", .M, 6, .mainSequence, mass: 0.14, radius: 0.16, temp: 2_799)]),
        CatalogueEntry("Epsilon Eridani", ra: (3, 32, 55.8), dec: (-9, 27, 30), ly: 10.47,
                       [CatalogueStar("", .K, 2, .mainSequence, mass: 0.82, radius: 0.74, temp: 5_084)],
                       planets: [KnownPlanet("b", au: 3.5, mass: 210)]),
        CatalogueEntry("Lacaille 9352", ra: (23, 5, 52.0), dec: (-35, 51, 11), ly: 10.72,
                       [CatalogueStar("", .M, 0.5, .mainSequence, mass: 0.48, radius: 0.47, temp: 3_688)],
                       planets: [KnownPlanet("b", au: 0.068, mass: 4.2), KnownPlanet("c", au: 0.12, mass: 7.6)]),
        CatalogueEntry("Ross 128", ra: (11, 47, 44.4), dec: (0, 48, 16), ly: 11.01,
                       [CatalogueStar("", .M, 4, .mainSequence, mass: 0.17, radius: 0.20, temp: 3_192)],
                       planets: [KnownPlanet("b", au: 0.0496, mass: 1.4)]),
        CatalogueEntry("EZ Aquarii", ra: (22, 38, 33.4), dec: (-15, 18, 7), ly: 11.1, [
            CatalogueStar("A", .M, 5, .mainSequence, mass: 0.11),
            CatalogueStar("C", .M, 5.5, .mainSequence, sep: 0.035, mass: 0.10),
            CatalogueStar("B", .M, 6, .mainSequence, sep: 1.4, mass: 0.10),
        ]),
        CatalogueEntry("61 Cygni", ra: (21, 6, 53.9), dec: (38, 44, 58), ly: 11.40, [
            CatalogueStar("A", .K, 5, .mainSequence, mass: 0.70, radius: 0.67, temp: 4_526),
            CatalogueStar("B", .K, 7, .mainSequence, sep: 84, mass: 0.63, radius: 0.60, temp: 4_077),
        ]),
        CatalogueEntry("Procyon", ra: (7, 39, 18.1), dec: (5, 13, 30), ly: 11.46, [
            CatalogueStar("A", .F, 5, .subgiant, mass: 1.50, radius: 2.05, temp: 6_530),
            CatalogueStar("B", .whiteDwarf, 0, .none, sep: 15, mass: 0.60, radius: 0.012, temp: 7_740),
        ]),
        CatalogueEntry("Struve 2398", ra: (18, 42, 46.7), dec: (59, 37, 49), ly: 11.49, [
            CatalogueStar("A", .M, 3, .mainSequence, mass: 0.33),
            CatalogueStar("B", .M, 3.5, .mainSequence, sep: 56, mass: 0.25),
        ]),
        CatalogueEntry("Groombridge 34", ra: (0, 18, 22.9), dec: (44, 1, 23), ly: 11.62, [
            CatalogueStar("A", .M, 1.5, .mainSequence, mass: 0.38),
            CatalogueStar("B", .M, 3.5, .mainSequence, sep: 147, mass: 0.15),
        ]),
        CatalogueEntry("Epsilon Indi", ra: (22, 3, 21.7), dec: (-56, 47, 10), ly: 11.87, [
            CatalogueStar("A", .K, 5, .mainSequence, mass: 0.76, radius: 0.71, temp: 4_649),
            CatalogueStar("Ba", .T, 1, .none, sep: 1_460, mass: 0.066),
            CatalogueStar("Bb", .T, 6, .none, sep: 1_460, mass: 0.053),
        ], planets: [KnownPlanet("Ab", au: 11.6, mass: 2_000)]),
        CatalogueEntry("DX Cancri", ra: (8, 29, 49.3), dec: (26, 46, 37), ly: 11.82,
                       [CatalogueStar("", .M, 6.5, .mainSequence, mass: 0.09)]),
        CatalogueEntry("Tau Ceti", ra: (1, 44, 4.1), dec: (-15, 56, 15), ly: 11.91,
                       [CatalogueStar("", .G, 8, .mainSequence, mass: 0.78, radius: 0.79, temp: 5_344)]),
        CatalogueEntry("Gliese 1061", ra: (3, 36, 0.0), dec: (-44, 30, 46), ly: 11.98,
                       [CatalogueStar("", .M, 5.5, .mainSequence, mass: 0.12)],
                       planets: [KnownPlanet("b", au: 0.021, mass: 1.4), KnownPlanet("c", au: 0.035, mass: 1.8),
                                 KnownPlanet("d", au: 0.054, mass: 1.6)]),
        CatalogueEntry("YZ Ceti", ra: (1, 12, 30.6), dec: (-16, 59, 56), ly: 12.1,
                       [CatalogueStar("", .M, 4.5, .mainSequence, mass: 0.13)],
                       planets: [KnownPlanet("b", au: 0.016, mass: 0.7), KnownPlanet("c", au: 0.022, mass: 1.1),
                                 KnownPlanet("d", au: 0.028, mass: 1.1)]),
        CatalogueEntry("Luyten's Star", ra: (7, 27, 24.5), dec: (5, 13, 33), ly: 12.35,
                       [CatalogueStar("", .M, 3.5, .mainSequence, mass: 0.26)],
                       planets: [KnownPlanet("c", au: 0.036, mass: 1.2), KnownPlanet("b", au: 0.091, mass: 2.9)]),
        CatalogueEntry("Teegarden's Star", ra: (2, 53, 0.9), dec: (16, 52, 53), ly: 12.50,
                       [CatalogueStar("", .M, 7, .mainSequence, mass: 0.09, radius: 0.11, temp: 2_904)],
                       planets: [KnownPlanet("b", au: 0.0259, mass: 1.05), KnownPlanet("c", au: 0.0455, mass: 1.11)]),
        CatalogueEntry("Kapteyn's Star", ra: (5, 11, 40.6), dec: (-45, 1, 6), ly: 12.83,
                       [CatalogueStar("", .M, 1, .mainSequence, mass: 0.27, radius: 0.29, temp: 3_570)]),
        CatalogueEntry("Lacaille 8760", ra: (21, 17, 15.3), dec: (-38, 52, 3), ly: 12.95,
                       [CatalogueStar("", .M, 0, .mainSequence, mass: 0.60, radius: 0.51, temp: 3_800)]),
        CatalogueEntry("Kruger 60", ra: (22, 27, 59.5), dec: (57, 41, 45), ly: 13.07, [
            CatalogueStar("A", .M, 3, .mainSequence, mass: 0.27),
            CatalogueStar("B", .M, 4, .mainSequence, sep: 9.5, mass: 0.18),
        ]),

        // Famous bright stars further out.
        CatalogueEntry("Altair", ra: (19, 50, 47.0), dec: (8, 52, 6), ly: 16.73,
                       [CatalogueStar("", .A, 7, .mainSequence, mass: 1.86, radius: 1.8, temp: 7_670)]),
        CatalogueEntry("Vega", ra: (18, 36, 56.3), dec: (38, 47, 1), ly: 25.04,
                       [CatalogueStar("", .A, 0, .mainSequence, mass: 2.14, radius: 2.36, temp: 9_600)]),
        CatalogueEntry("Fomalhaut", ra: (22, 57, 39.0), dec: (-29, 37, 20), ly: 25.13,
                       [CatalogueStar("", .A, 3, .mainSequence, mass: 1.92, radius: 1.84, temp: 8_590)]),
        CatalogueEntry("Pollux", ra: (7, 45, 18.9), dec: (28, 1, 34), ly: 33.78,
                       [CatalogueStar("", .K, 0, .giant, mass: 1.91, radius: 9.06, temp: 4_586)],
                       planets: [KnownPlanet("b", au: 1.64, mass: 730)]),
        CatalogueEntry("Arcturus", ra: (14, 15, 39.7), dec: (19, 10, 57), ly: 36.7,
                       [CatalogueStar("", .K, 1.5, .giant, mass: 1.08, radius: 25.4, temp: 4_286)]),
        CatalogueEntry("Capella", ra: (5, 16, 41.4), dec: (45, 59, 53), ly: 42.9, [
            CatalogueStar("Aa", .G, 8, .giant, mass: 2.57, radius: 11.98, temp: 4_970),
            CatalogueStar("Ab", .G, 0, .giant, sep: 0.74, mass: 2.48, radius: 8.83, temp: 5_730),
        ]),
        CatalogueEntry("Castor", ra: (7, 34, 35.9), dec: (31, 53, 18), ly: 51, [
            CatalogueStar("A", .A, 1, .mainSequence, mass: 2.4, radius: 2.4, temp: 10_300),
            CatalogueStar("B", .A, 2, .mainSequence, sep: 104, mass: 2.0, radius: 1.6, temp: 8_300),
        ]),
        CatalogueEntry("Aldebaran", ra: (4, 35, 55.2), dec: (16, 30, 33), ly: 65.3,
                       [CatalogueStar("", .K, 5, .giant, mass: 1.16, radius: 45, temp: 3_900)]),
        CatalogueEntry("Regulus", ra: (10, 8, 22.3), dec: (11, 58, 2), ly: 79.3,
                       [CatalogueStar("", .B, 8, .subgiant, mass: 3.8, radius: 3.5, temp: 12_460)]),
        CatalogueEntry("Achernar", ra: (1, 37, 42.8), dec: (-57, 14, 12), ly: 139,
                       [CatalogueStar("", .B, 6, .mainSequence, mass: 6.7, radius: 9.2, temp: 15_000)]),
        CatalogueEntry("Spica", ra: (13, 25, 11.6), dec: (-11, 9, 41), ly: 250, [
            CatalogueStar("A", .B, 1, .giant, mass: 11.4, radius: 7.5, temp: 22_400),
            CatalogueStar("B", .B, 2, .mainSequence, sep: 0.12, mass: 7.2, radius: 3.6, temp: 18_500),
        ]),
        CatalogueEntry("Canopus", ra: (6, 23, 57.1), dec: (-52, 41, 44), ly: 310,
                       [CatalogueStar("", .A, 9, .brightGiant, mass: 8, radius: 71, temp: 7_400)]),
        CatalogueEntry("Polaris", ra: (2, 31, 49.1), dec: (89, 15, 51), ly: 433,
                       [CatalogueStar("", .F, 7, .supergiant, mass: 5.4, radius: 37.5, temp: 6_015)]),
        CatalogueEntry("Alcyone", ra: (3, 47, 29.1), dec: (24, 6, 18), ly: 440,
                       [CatalogueStar("", .B, 7, .giant, mass: 6, radius: 9.3, temp: 12_260)]),
        CatalogueEntry("Betelgeuse", ra: (5, 55, 10.3), dec: (7, 24, 25), ly: 548,
                       [CatalogueStar("", .M, 1.5, .supergiant, mass: 18, radius: 764, temp: 3_600)]),
        CatalogueEntry("Antares", ra: (16, 29, 24.5), dec: (-26, 25, 55), ly: 550, [
            CatalogueStar("A", .M, 1.5, .supergiant, mass: 12, radius: 680, temp: 3_660),
            CatalogueStar("B", .B, 2.5, .mainSequence, sep: 529, mass: 7.2, radius: 5.2, temp: 18_500),
        ]),
        CatalogueEntry("Rigel", ra: (5, 14, 32.3), dec: (-8, 12, 6), ly: 860,
                       [CatalogueStar("", .B, 8, .supergiant, mass: 21, radius: 79, temp: 12_100)]),
        CatalogueEntry("Deneb", ra: (20, 41, 25.9), dec: (45, 16, 49), ly: 2_600,
                       [CatalogueStar("", .A, 2, .supergiant, mass: 19, radius: 203, temp: 8_525)]),

        // The supermassive black hole at the heart of the galaxy.
        CatalogueEntry("Sagittarius A*", position: .galacticCentre,
                       [CatalogueStar("", .blackHole, 0, .none, mass: 4.3e6, radius: 18.2, temp: 0)]),
    ]

    /// Index of each entry by lowercased name.
    static let nameIndex: [String: Int] = {
        var d: [String: Int] = [:]
        for (i, e) in entries.enumerated() { d[e.name.lowercased()] = i }
        return d
    }()
}
