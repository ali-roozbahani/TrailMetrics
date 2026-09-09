// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "History",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "History", targets: ["History"])
    ],
    dependencies: [
        .package(path: "../SharedKit")
    ],
    targets: [
        .target(
            name: "History",
            dependencies: ["SharedKit"]
        )
    ]
)
