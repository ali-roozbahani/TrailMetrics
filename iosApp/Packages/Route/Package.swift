// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Route",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Route", targets: ["Route"])
    ],
    dependencies: [
        .package(path: "../DesignSystem"),
        .package(path: "../SharedKit"),
        .package(path: "../TestSupport"),
        .package(url: "https://github.com/googlemaps/ios-maps-sdk", from: "11.1.0")
    ],
    targets: [
        .target(
            name: "Route",
            dependencies: [
                "DesignSystem",
                "SharedKit",
                .product(name: "GoogleMaps", package: "ios-maps-sdk")
            ],
            resources: [.process("Localizable.xcstrings")]
        ),
        .testTarget(
            name: "RouteTests",
            dependencies: ["Route", "TestSupport"]
        )
    ]
)
