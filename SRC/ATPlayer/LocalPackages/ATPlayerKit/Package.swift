// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ATPlayerKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "PlayerApplication", targets: ["PlayerApplication"]),
        .library(name: "PlaybackActivity", targets: ["PlaybackActivity"]),
        .library(name: "AppLocalization", targets: ["AppLocalization"])
    ],
    targets: [
        .target(name: "AppLocalization", resources: [.process("Resources")]),
        .target(name: "LibraryDomain"),
        .target(name: "FolderDomain", dependencies: ["AppLocalization"]),
        .target(name: "FolderFeature", dependencies: ["AppLocalization", "FolderDomain"]),
        .target(name: "PlaybackDomain", dependencies: ["AppLocalization"]),
        .target(name: "PlaybackActivity"),
        .target(name: "PlayerInfrastructure", dependencies: ["AppLocalization", "LibraryDomain", "PlaybackDomain", "PlaybackActivity", "FolderDomain"]),
        .target(name: "PlayerFeature", dependencies: ["AppLocalization", "LibraryDomain", "PlaybackDomain", "FolderDomain"],
                resources: [.process("Resources")]),
        .target(name: "PlayerApplication", dependencies: ["AppLocalization", "PlayerFeature", "FolderFeature", "FolderDomain", "PlayerInfrastructure", "PlaybackDomain"]),
        .target(name: "LegacyPlaylistFixture", path: "Tests/LegacyPlaylistFixture"),
        .testTarget(name: "AppLocalizationTests", dependencies: ["AppLocalization"]),
        .testTarget(name: "PlaybackActivityTests", dependencies: ["PlaybackActivity"]),
        .testTarget(name: "PlayerInfrastructureTests", dependencies: ["PlayerInfrastructure", "PlayerFeature", "LibraryDomain", "FolderDomain", "LegacyPlaylistFixture"], resources: [.copy("Fixtures")]),
        .testTarget(name: "PlayerFeatureTests", dependencies: ["PlayerFeature", "PlaybackDomain", "LibraryDomain", "FolderDomain"]),
        .testTarget(name: "FolderFeatureTests", dependencies: ["FolderFeature", "FolderDomain"])
    ],
    swiftLanguageModes: [.v5]
)
