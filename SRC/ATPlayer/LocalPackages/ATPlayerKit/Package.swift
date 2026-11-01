// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ATPlayerKit",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "PlayerApplication", targets: ["PlayerApplication"]),
        .library(name: "PlaybackActivity", targets: ["PlaybackActivity"])
    ],
    targets: [
        .target(name: "LibraryDomain"),
        .target(name: "PlaybackDomain"),
        .target(name: "PlaybackActivity"),
        .target(name: "PlayerInfrastructure", dependencies: ["LibraryDomain", "PlaybackDomain", "PlaybackActivity"]),
        .target(name: "PlayerFeature", dependencies: ["LibraryDomain", "PlaybackDomain"]),
        .target(name: "PlayerApplication", dependencies: ["PlayerFeature", "PlayerInfrastructure", "PlaybackDomain"]),
        .target(name: "LegacyPlaylistFixture", path: "Tests/LegacyPlaylistFixture"),
        .testTarget(name: "PlayerInfrastructureTests", dependencies: ["PlayerInfrastructure", "LibraryDomain", "LegacyPlaylistFixture"]),
        .testTarget(name: "PlayerFeatureTests", dependencies: ["PlayerFeature", "PlaybackDomain", "LibraryDomain"])
    ],
    swiftLanguageModes: [.v5]
)
