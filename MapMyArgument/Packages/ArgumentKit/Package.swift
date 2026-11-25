// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ArgumentKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ArgumentKit", targets: ["ArgumentKit"]),
    ],
    targets: [
        .target(name: "ArgumentKit"),
        .testTarget(name: "ArgumentKitTests", dependencies: ["ArgumentKit"], resources: [.copy("Fixtures")]),
    ]
)
