// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PineappleCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "PineappleCore", targets: ["PineappleCore"])],
    targets: [
        .target(name: "PineappleCore"),
        .testTarget(name: "PineappleCoreTests", dependencies: ["PineappleCore"])
    ]
)
