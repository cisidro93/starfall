// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StarfallGalaxy",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StarfallGalaxy", targets: ["StarfallGalaxy"]),
        .executable(name: "galaxy-cli", targets: ["galaxy-cli"]),
    ],
    targets: [
        .target(name: "StarfallGalaxy"),
        .executableTarget(name: "galaxy-cli", dependencies: ["StarfallGalaxy"]),
        .testTarget(name: "StarfallGalaxyTests", dependencies: ["StarfallGalaxy"]),
    ]
)
