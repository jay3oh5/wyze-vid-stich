// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WyzeVidStitch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "WyzeVidStitch",
            targets: ["WyzeVidStitch"]
        )
    ],
    dependencies: [
        .package(path: "Packages/WyzeStitcherKit")
    ],
    targets: [
        .executableTarget(
            name: "WyzeVidStitch",
            dependencies: [
                .product(name: "WyzeStitcherKit", package: "WyzeStitcherKit")
            ],
            path: "WyzeVidStitch",
            exclude: [
                "WyzeVidStitch.entitlements"
            ]
        )
    ]
)
