// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tracking",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Tracking", targets: ["Tracking"])
    ],
    dependencies: [
        .package(path: "../SharedKit"),
        .package(url: "https://github.com/googlemaps/ios-maps-sdk", from: "11.1.0")
    ],
    targets: [
        .target(
            name: "Tracking",
            dependencies: [
                "SharedKit",
                .product(name: "GoogleMaps", package: "ios-maps-sdk")
            ]
        )
    ]
)
