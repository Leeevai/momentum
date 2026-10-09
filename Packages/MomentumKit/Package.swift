// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MomentumKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "MomentumCore", targets: ["MomentumCore"]),
    ],
    targets: [
        .target(name: "MomentumCore"),
        .testTarget(
            name: "MomentumCoreTests",
            dependencies: ["MomentumCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
