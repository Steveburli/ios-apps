// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ThoughtsKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ThoughtsKit", targets: ["ThoughtsKit"]),
    ],
    targets: [
        .target(name: "ThoughtsKit"),
        .testTarget(name: "ThoughtsKitTests", dependencies: ["ThoughtsKit"]),
    ]
)
