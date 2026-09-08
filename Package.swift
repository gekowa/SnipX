// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnipX",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SnipX", targets: ["SnipX"])],
    targets: [
        .target(name: "SnipCore"),
        .executableTarget(name: "SnipX", dependencies: ["SnipCore"]),
        .testTarget(name: "SnipCoreTests", dependencies: ["SnipCore"]),
        .testTarget(name: "SnipXTests", dependencies: ["SnipX"])
    ],
    swiftLanguageModes: [.v5]
)
