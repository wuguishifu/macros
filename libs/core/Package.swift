// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacrosCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacrosCore", targets: ["MacrosCore"])
    ],
    targets: [
        .target(name: "MacrosCore"),
        .testTarget(name: "MacrosCoreTests", dependencies: ["MacrosCore"]),
    ]
)
