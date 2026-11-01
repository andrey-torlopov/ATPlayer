# Architecture refactoring — 2026-11-01

Architecture-only phase, before the folder feature. The `.xcodeproj` remains the app entry point and links the local `ATPlayerKit` package.

## Verified

- App and widget: `xcodebuild -project SRC/ATPlayer/ATPlayer.xcodeproj -scheme ATPlayer -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ATPlayerArchitectureDerived CODE_SIGNING_ALLOWED=NO build` — BUILD SUCCEEDED.
- Package: from `SRC/ATPlayer/LocalPackages/ATPlayerKit`, `xcodebuild -scheme ATPlayerKit-Package -destination 'platform=iOS Simulator,id=A0EA97FA-8776-4762-96D7-CEA800200E5A' -derivedDataPath /tmp/ATPlayerPackageDerived -resultBundlePath /tmp/ATPlayerArchitecturePackageTests.xcresult CODE_SIGNING_ALLOWED=NO test` — TEST SUCCEEDED.
- XCTest result calculated from passed/failed case records: passed / total = 16 / 16; failures = 0.
- The original SwiftData schema written from a separate fixture module opens, retains IDs/order/bookmarks/artwork/relationships and can be edited and reopened through the relocated adapter.
- Existing ordinary/repeat/shuffle behavior, stale download cancellation by Pause, preferences, scoped deletion and disk persistence are tested. A real AVAudioEngine starts, pauses, resumes, seeks and finishes in the simulator.
- `plutil -lint` validates the Xcode project; `git diff --check` validates whitespace.

## Boundaries

No folder feature is included in this phase. V0/V1 presentation and saved playlist/defaults formats are retained. Source files are grouped into domain, infrastructure, feature and application targets; the widget only links ActivityKit attributes. Package XCTest uses its own generated `ATPlayerKit-Package` scheme; the app scheme has no test bundles.

A simulator run does not establish physical-device behavior for iCloud/SMB, interruptions, Bluetooth/AirPlay or Live Activity on the lock screen. Existing test artifacts under this directory describe the earlier source layout; the package XCTest suite supersedes their source-compilation harness.

The user's pre-existing `UserInterfaceState.xcuserstate` modification is excluded from the commit.
