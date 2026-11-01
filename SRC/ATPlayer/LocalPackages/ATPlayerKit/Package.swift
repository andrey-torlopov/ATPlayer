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
        .target(name: "FolderDomain"),
        .target(name: "FolderFeature", dependencies: ["FolderDomain"]),
        .target(name: "PlaybackDomain"),
        .target(name: "PlaybackActivity"),
        .target(name: "PlayerInfrastructure", dependencies: ["LibraryDomain", "PlaybackDomain", "PlaybackActivity", "FolderDomain"]),
        .target(name: "PlayerFeature", dependencies: ["LibraryDomain", "PlaybackDomain", "FolderDomain"]),
        .target(name: "PlayerApplication", dependencies: ["PlayerFeature", "FolderFeature", "FolderDomain", "PlayerInfrastructure", "PlaybackDomain"]),
        .target(name: "LegacyPlaylistFixture", path: "Tests/LegacyPlaylistFixture"),
        .testTarget(name: "PlayerInfrastructureTests", dependencies: ["PlayerInfrastructure", "LibraryDomain", "FolderDomain", "LegacyPlaylistFixture"]),
        .testTarget(name: "PlayerFeatureTests", dependencies: ["PlayerFeature", "PlaybackDomain", "LibraryDomain", "FolderDomain"]),
        .testTarget(name: "FolderFeatureTests", dependencies: ["FolderFeature", "FolderDomain"])
    ],
    swiftLanguageModes: [.v5]
)
