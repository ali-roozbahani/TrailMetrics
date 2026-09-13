// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Route",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Route", targets: ["Route"])
    ],
    dependencies: [
        .package(path: "../SharedKit"),
        .package(url: "https://github.com/googlemaps/ios-maps-sdk", from: "9.0.0")
    ],
    targets: [
        .target(
            name: "Route",
            dependencies: [
                "SharedKit",
                .product(name: "GoogleMaps", package: "ios-maps-sdk")
            ]
        )
    ]
)
