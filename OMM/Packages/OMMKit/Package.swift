// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OMMKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OMMKit", targets: ["OMMKit"]),
    ],
    targets: [
        .target(name: "OMMKit"),
        .testTarget(name: "OMMKitTests", dependencies: ["OMMKit"]),
    ]
)
