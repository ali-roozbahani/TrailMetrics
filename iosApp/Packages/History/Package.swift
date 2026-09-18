// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "History",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "History", targets: ["History"])
    ],
    dependencies: [
        .package(path: "../DesignSystem"),
        .package(path: "../SharedKit"),
        .package(url: "https://github.com/googlemaps/ios-maps-sdk", from: "11.1.0")
    ],
    targets: [
        .target(
            name: "History",
            dependencies: [
                "DesignSystem",
                "SharedKit",
                .product(name: "GoogleMaps", package: "ios-maps-sdk")
            ]
        )
    ]
)
