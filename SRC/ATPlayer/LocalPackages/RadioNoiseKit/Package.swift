// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RadioNoiseKit",
    products: [
        .library(name: "RadioNoiseKit", targets: ["RadioNoiseKit"]),
        .library(name: "RadioNoiseAssets", targets: ["RadioNoiseAssets"])
    ],
    targets: [
        .target(name: "RadioNoiseKit", publicHeadersPath: "include"),
        .target(name: "RadioNoiseAssets", resources: [.process("Resources")]),
        .testTarget(name: "RadioNoiseKitTests", dependencies: ["RadioNoiseKit"]),
        .testTarget(name: "RadioNoiseAssetsTests", dependencies: ["RadioNoiseAssets"])
    ],
    cxxLanguageStandard: .cxx17
)
