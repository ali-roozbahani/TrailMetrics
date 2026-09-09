// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SharedKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SharedKit", targets: ["SharedKit"])
    ],
    targets: [
        .binaryTarget(
            name: "TrailMetricsShared",
            path: "../../../shared/build/XCFrameworks/debug/TrailMetricsShared.xcframework"
        ),
        .target(
            name: "SharedKit",
            dependencies: ["TrailMetricsShared"]
        )
    ]
)
