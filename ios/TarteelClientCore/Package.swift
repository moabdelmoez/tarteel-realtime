// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TarteelClientCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "TarteelClientCore",
            targets: ["TarteelClientCore"]
        ),
        .executable(
            name: "coreml-fixture-runner",
            targets: ["CoreMLFixtureRunner"]
        ),
    ],
    targets: [
        .target(name: "TarteelClientCore"),
        .executableTarget(
            name: "CoreMLFixtureRunner",
            dependencies: ["TarteelClientCore"]
        ),
        .testTarget(
            name: "TarteelClientCoreTests",
            dependencies: ["TarteelClientCore"]
        ),
    ]
)
