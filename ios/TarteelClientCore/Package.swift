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
    ],
    targets: [
        .target(name: "TarteelClientCore"),
        .testTarget(
            name: "TarteelClientCoreTests",
            dependencies: ["TarteelClientCore"]
        ),
    ]
)
