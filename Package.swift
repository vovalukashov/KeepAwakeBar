// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeepAwakeCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "KeepAwakeCore", targets: ["KeepAwakeCore"])],
    targets: [
        .target(name: "KeepAwakeCore", path: "KeepAwakeBar/Core"),
        .testTarget(name: "KeepAwakeCoreTests", dependencies: ["KeepAwakeCore"])
    ]
)
