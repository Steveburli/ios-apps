// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LittlesKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LittlesKit", targets: ["LittlesKit"]),
    ],
    targets: [
        .target(name: "LittlesKit"),
        .testTarget(name: "LittlesKitTests", dependencies: ["LittlesKit"]),
    ]
)
