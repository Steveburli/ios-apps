// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MutualKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MutualKit", targets: ["MutualKit"]),
    ],
    targets: [
        .target(name: "MutualKit"),
        .testTarget(name: "MutualKitTests", dependencies: ["MutualKit"]),
    ]
)
