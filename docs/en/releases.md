# Release status and verification

*[Русский](../ru/releases.md)*

## 1.5.0 — November 14, 2026

**Status: Waiting for Review.** Version **1.5.0**, build **7**, was submitted to App Review on **November 14, 2026, around 22:19 Moscow time**. App Store Connect showed **1 Item Submitted** and **1.5.0 Waiting for Review**. [View the submission](https://appstoreconnect.apple.com/apps/6829444190/distribution/reviewsubmissions/details/0ee7de22-7e33-4ca0-b67f-18220a22b53f) (account access required).

App and widget require **iOS / iPadOS 26.0 or later**. Upload succeeded at **22:15 Moscow time**, and processing completed before submission. Automatic release after approval remains enabled. Version 1.5.0 is not yet publicly released; the preceding **1.2.0** version is marked **Ready for Distribution** in App Store Connect.

### What changed

- Optional radio texture, with noise rising and falling smoothly as the music becomes quieter.
- **Radio is off on first launch:** both controls start at 0. Previously saved choices are preserved.
- Separate **Radio effect** and **Radio effect background** sliders, each from 0 to 10. The background cannot exceed the maximum: adjusting beyond the other control moves both together.
- Background 0 allows quiet intervals. A positive background maintains radio texture during playback; equal levels keep the noise near one level with natural variation.
- A reduced maximum: level 10 corresponds to level 7 from the earlier development build. The recorded texture is balanced to soften sharp peaks and avoid abrupt silent gaps.
- Ordinary track transitions without station-search sounds or FM/AM selection. Pause, Stop and the end of playback silence the effect.

Radio processing is local. It does not use the microphone or connect to radio stations. See [radio controls](features.md#radio-effect-in-150).

### Development and verification

The standalone **RadioNoiseKit** Swift package contains the processing core and recorded-noise assets. **NoiseDemo** for iOS / iPadOS 18 or later supports comparing the recording, experimental synthesis and imported music; it is a separate development project.

Fresh checks for 1.5.0 passed: **196 of 196** ATPlayerKit tests on the iOS 26.3.1 simulator and **37 of 37** RadioNoiseKit/assets tests, with no failures. A new Release archive and App Store Connect IPA export succeeded. Both app and widget signatures, version **1.5.0 (7)**, minimum OS **26.0**, provisioning and the bundled noise resource were verified. The upload completed successfully, server processing finished, and build 7 was selected and submitted with version 1.5.0.

NoiseDemo’s **12 of 12** passing tests belong to the preceding audio iteration and were not rerun for this release. Logs, test results, signature checks and the upload receipt are retained locally in `Artifacts/Release-1.5.0/`.

[Radio effect announcement on Boosty (Russian)](https://boosty.to/andreytorlopov/posts/e2ab562c-5d8e-4d6b-82f8-65ebf96bf9e7).

Physical audio-route acceptance, extended playback and realtime timing remain separate checks. The known first 200 ms peak limitation when enabling processing on already-overloaded EQ input remains. No playlist database migration is required.

## Previous local candidate — 1.3.1 (5)

A local **1.3.1 (5)** candidate is prepared for **iOS / iPadOS 26.0 or later**. The changes stabilize layout when starting the first track, reconcile actual audio-output state before Play/Toggle, and immediately publish pauses to system controls. Short background tasks protect asynchronous audio startup and Live Activity updates. Resource cleanup avoids the isolated-deinit runtime path that crashes on early iOS 26 releases.

Full XCTest on the iOS 26.3 simulator: **passed / total = 132 / 137**, **0** failures and **5** skipped tests requiring an unavailable optional user-supplied MP3. A local Release archive was created. Physical AirPods, incoming calls while locked, and execution on iOS 26.0 itself remain separate checks. This version has not been uploaded to App Store Connect or submitted for review.

The candidate retains Russian/English localization, language selection, and appearance settings from the 1.3.0 preparation. Local verification does not establish public release status.

The records below are historical snapshots from **November 1, 2026**.

## Historical candidate — 1.1.0 (2)

**Version 1.1.0, build 2** was submitted to App Review on **November 1, 2026 at 22:28 Moscow time**. At that time, App Store Connect showed **Waiting for Review**, one submitted item, and no draft submissions. Automatic release after approval is enabled. Public release had not occurred at that time. The archive upload succeeded earlier at **22:20:39 Moscow time**; processing completed before submission.

The candidate includes playback modes, the **Playlists / Folders** switch, current-level folder queues and temporary local audio caching, filtering of folders without supported audio, playlist reordering, and the Feature-First SwiftPM refactoring. These features are implemented and packaged. Browsing and playback remain separate: a directory metadata scan may inspect descendants to decide whether a folder contains music, but playback and prefetch use only the open level. See [playback behavior](features.md#playback).

| Item | Verified state for 1.1.0 (2) |
|---|---|
| Simulator app and extension build | Same functional code verified before the version/build number change; succeeded |
| XCTest | Same functional code before the version/build number change: passed / total = 53 / 53; no failures |
| Playlist-order UI | Dragging and persistence after relaunch verified in the QA simulator |
| Distribution archive | Created; version, build, app and extension signatures verified |
| Exported IPA | Created; app and extension signatures verified |
| App Store Connect upload | Succeeded at 22:20:39 Moscow time |
| Apple build processing | Completed; 1.1.0 (2) submitted |
| Russian and English metadata | Description, promotional text, keywords, and subtitle saved |
| App Review attachment | ATPlayer-Review-Demo.zip preserved |
| App Privacy | Published: Data Not Collected |
| New App Review submission | Submitted at 22:28 Moscow time; Waiting for Review |
| Submission contents | One submitted item; no draft submissions |
| Release mode | Automatic after approval |
| Public App Store release | Not performed |

Archive/upload logs and test/UI reports are retained locally and excluded from the source repository. The historical checks above are recorded from those reports. Real iCloud/SMB providers and physical-device behavior were not tested in that change; simulator and local-file tests do not establish those results.

The earlier **1.0.2 (1)** submission was withdrawn; App Store Connect showed **Developer Rejected**. The new [1.1.0 submission in App Store Connect](https://appstoreconnect.apple.com/apps/6829444190/distribution/reviewsubmissions/details/9cc2260c-8b1f-413b-a9c0-7d3e15bdc5a8) has ID `9cc2260c-8b1f-413b-a9c0-7d3e15bdc5a8` (account access required). The historical record below preserves the earlier 17:28 snapshot.

## Historical submission — 1.0.2 (1), 17:28 snapshot

**Version 1.0.2, build 1** was submitted to App Review on November 1, 2026 at **17:28 Moscow time**. At that time, App Store Connect showed **Waiting for Review**, with automatic release after approval enabled. The following table preserves that historical submission record; it does not describe the current release.

| Item | Recorded status |
|---|---|
| Minimum system | iOS / iPadOS 26.2 |
| Devices | iPhone and iPad |
| App interface | Russian |
| Planned price | Free, no in-app purchases |
| Privacy and support pages | Published on GitHub |
| Simulator build | Completed with Xcode 27.2 during release preparation |
| Distribution archive and IPA export | Completed; app and extension signatures verified |
| Upload to App Store Connect | Succeeded |
| Apple build processing | Completed; build attached to version 1.0.2 |
| Product-page texts | Russian and English saved |
| Screenshots | 4 iPhone and 2 iPad JPEGs uploaded; Russian and English localizations checked |
| Header and Search Results assets | Uploaded for Russian; English reuses these assets; Russian device previews checked |
| App Review attachment | Original CC0 demo audio and review instructions uploaded |
| App Privacy | Published |
| Availability settings | Free in 175 regions; Mac and Apple Vision availability disabled |
| Age rating | 4+ saved |
| App Review submission | Submitted November 1, 2026 at 17:28 Moscow time; Waiting for Review |
| Release mode | Automatic after approval |
| App Store public availability | Pending |

The owner has reported successful manual testing of the app. That report is not a complete device, file-format, accessibility, or audio-route test matrix. The earlier 1.0.2 release preparation also verified the bundle versions, device families, privacy manifest, and distribution signatures. These checks establish packaging facts; they do not guarantee App Review approval.

## Runtime checks that matter

For a playback change, cover local file import and access after relaunch, play/pause and seeking, track completion, an unavailable file, playlist changes, and background operation. For system integration changes, also check interruptions, connected audio devices, Lock Screen controls, and Live Activities on supported hardware.

For file-provider changes, test a downloaded local file and an iCloud file separately. Playlists store references, while Folders mode prepares temporary local copies. Neither guarantees persistent offline availability, so provider behavior and cache eviction are part of the scenario. Avoid inferring codec coverage from filename extensions alone.

## Updating documentation

After each new version becomes publicly available, update its status with the verified App Store link and release date. Keep the existing download link for the currently available version; do not describe an update as released while it is still a draft, in review, or available only to private testers.

Keep [privacy](../../PRIVACY.md) and [support](../../SUPPORT.md) current with the shipped app. Update the data policy before adding a data collection SDK, account, backend, or synchronization feature.

---

[Documentation](index.md) · [README](../../README.md)
