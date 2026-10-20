// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DoThisNowKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DoThisNowKit", targets: ["DoThisNowKit"]),
    ],
    targets: [
        .target(name: "DoThisNowKit"),
        .testTarget(name: "DoThisNowKitTests", dependencies: ["DoThisNowKit"]),
    ]
)
