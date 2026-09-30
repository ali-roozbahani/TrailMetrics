// swift-tools-version: 5.9
import PackageDescription

// Test doubles shared by two or more feature packages' test targets. Link the product only
// from a `.testTarget`, never from a feature's Sources/ target, so none of this reaches the app.
let package = Package(
    name: "TestSupport",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "TestSupport", targets: ["TestSupport"])
    ],
    dependencies: [
        .package(path: "../SharedKit")
    ],
    targets: [
        .target(
            name: "TestSupport",
            dependencies: ["SharedKit"]
        )
    ]
)
