// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WyzeStitcherKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "WyzeStitcherKit",
            targets: ["WyzeStitcherKit"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "WyzeStitcherCoreFFI",
            path: "WyzeStitcherCoreFFI.xcframework"
        ),
        .target(
            name: "WyzeStitcherKit",
            dependencies: ["WyzeStitcherCoreFFI"],
            path: "Sources/WyzeStitcherKit"
        )
    ]
)
