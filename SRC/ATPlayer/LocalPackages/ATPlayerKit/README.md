# ATPlayerKit

Local SwiftPM package connected to `../../ATPlayer.xcodeproj`. Open the existing Xcode project for the app; open `Package.swift` to run the automatically generated `ATPlayerKit-Package` test scheme.

## Module ownership

- `PlayerApplication`: process lifetime, production composition, external URL and AppIntent routing.
- `PlayerFeature`: playback/library session, playlist import orchestration, V0/V1 UI and settings. Depends only on domain contracts, not concrete services or SwiftData.
- `LibraryDomain`: playlist/track presentation entities and repository contract.
- `FolderDomain`: saved-root, direct-entry, cache-lease and source-storage contracts.
- `FolderFeature`: transient browser/navigation state and sequential current-level prefetch. Application injects this independent feature into the library slot; neither feature imports the other.
- `PlaybackDomain`: queue rules, audio state and playback/media/presentation contracts.
- `PlayerInfrastructure`: SwiftData, audio engine, file/bookmark access, Now Playing and Live Activity adapters.
- `PlaybackActivity`: shared ActivityKit attributes; the widget depends only on this product.

The executable owns app/scene entry points and configuration. Composition creates one playback session, including when launched for audio intents. The feature receives narrow dependencies through its initializer. System handlers call the application bridge; no feature-wide service locator remains.

The SwiftData model names, attributes, relationships and default container location are preserved. Domain objects are mapped by UUID and retain identity. Root-level `LegacyPlaylistFixture` test models reproduce the original schema in another module so the compatibility test can write an old database, reopen it through the new adapter, change it and reopen it again.

V0 remains available through the existing internal design switch. The active V1 offers Playlists/Folders; changing the library view never changes the active audio queue. Folder contents, navigation and queues are transient; only selected roots are saved in a separate JSON file. The playlist SwiftData schema stays unchanged.

## Checks

App and widget build:

```sh
xcodebuild -project SRC/ATPlayer/ATPlayer.xcodeproj -scheme ATPlayer \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/ATPlayerDerived CODE_SIGNING_ALLOWED=NO build
```

Before building package tests, install FFmpeg and generate the local audio fixtures. Audio files are ignored by Git; the test bundle copies the generated files.

```sh
python3 Tools/generate_audio_fixtures.py
```

Package tests (run from this directory; select an installed simulator):

```sh
xcodebuild -scheme ATPlayerKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath /tmp/ATPlayerTests CODE_SIGNING_ALLOWED=NO test
```

Tests cover persistent data compatibility, playlist transactions, playback queue modes, stale preparation cancellation, preferences, direct folder listing, root persistence, cache versioning/pinning/cancellation, and actual AVAudioEngine playback from a cached copy after the source disappears. Test doubles use production contracts; data and preferences are isolated. A simulator does not verify real File Providers, physical audio routes or lock-screen behavior on an iPhone.
