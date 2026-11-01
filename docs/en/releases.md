# Release status and verification

*[Русский](../ru/releases.md)*

Status recorded on **November 1, 2026**.

## Current candidate — 1.1.0 (2)

**Version 1.1.0, build 2** was submitted to App Review on **November 1, 2026 at 22:28 Moscow time**. App Store Connect shows **Waiting for Review**, one submitted item, and no draft submissions. Automatic release after approval is enabled. Public release has not occurred. The archive upload succeeded earlier at **22:20:39 Moscow time**; processing completed before submission.

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

Evidence: [archive verification](../../Artifacts/AppStore-1.1.0-2026-11-01/archive-verification.json), [IPA verification](../../Artifacts/AppStore-1.1.0-2026-11-01/ipa-verification.json), [upload result](../../Artifacts/AppStore-1.1.0-2026-11-01/upload-result.json), and [test/UI verification](../../Artifacts/PlaybackModes-2026-11-01/folder-filter-and-playlist-order-verification.md). The test report records the Python calculation behind the test count. Real iCloud/SMB providers and physical-device behavior were not tested in this change; simulator and local-file tests do not establish those results.

The earlier **1.0.2 (1)** submission was withdrawn; App Store Connect showed **Developer Rejected**. The new [1.1.0 submission in App Store Connect](https://appstoreconnect.apple.com/apps/6829444190/distribution/reviewsubmissions/details/9cc2260c-8b1f-413b-a9c0-7d3e15bdc5a8) has ID `9cc2260c-8b1f-413b-a9c0-7d3e15bdc5a8` (account access required). The historical record below preserves the earlier 17:28 snapshot.

## Historical submission — 1.0.2 (1), 17:28 snapshot

**Version 1.0.2, build 1** was submitted to App Review on November 1, 2026 at **17:28 Moscow time**. At that time, App Store Connect showed **Waiting for Review**, with automatic release after approval enabled. The following table preserves that historical submission record; it does not describe the current 1.1.0 candidate.

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

When Apple makes the app publicly available, replace the preparation status with the verified App Store link and release date. Do not add a download badge while the listing is only a draft, in review, or available to private testers.

Keep [privacy](../../PRIVACY.md) and [support](../../SUPPORT.md) current with the shipped app. Update the data policy before adding a data collection SDK, account, backend, or synchronization feature.

---

[Documentation](index.md) · [README](../../README.md)
