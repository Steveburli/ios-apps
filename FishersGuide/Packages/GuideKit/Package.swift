// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GuideKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GuideKit", targets: ["GuideKit"]),
    ],
    targets: [
        .target(name: "GuideKit", resources: [.process("Resources")]),
        .testTarget(name: "GuideKitTests", dependencies: ["GuideKit"]),
    ]
)
