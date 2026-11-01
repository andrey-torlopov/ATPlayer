# Release status and verification

*[Русский](../ru/releases.md)*

Status recorded on **November 1, 2026**.

## App Store candidate

**Version 1.0.2, build 1** was uploaded successfully to App Store Connect on November 1, 2026 at 16:39 Moscow time. Apple was processing the build when the upload completed. It has not yet been submitted to App Review and is not publicly available on the App Store. Source tags and a signed archive are separate from Apple's review and public availability.

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
| Apple build processing | In progress at upload completion |
| App Review submission | Pending |
| App Store public availability | Pending |

The owner has reported successful manual testing of the app. That report is not a complete device, file-format, accessibility, or audio-route test matrix. Current release preparation also verified the bundle versions, device families, privacy manifest, and distribution signatures. These checks establish packaging facts; they do not guarantee App Review approval.

## Runtime checks that matter

For a playback change, cover local file import and access after relaunch, play/pause and seeking, track completion, an unavailable file, playlist changes, and background operation. For system integration changes, also check interruptions, connected audio devices, Lock Screen controls, and Live Activities on supported hardware.

For file-provider changes, test a downloaded local file and an iCloud file separately. The player stores references rather than copies, so provider behavior is part of the scenario. Avoid inferring codec coverage from filename extensions alone.

## Updating documentation

When Apple makes the app publicly available, replace the preparation status with the verified App Store link and release date. Do not add a download badge while the listing is only a draft, in review, or available to private testers.

Keep [privacy](../../PRIVACY.md) and [support](../../SUPPORT.md) current with the shipped app. Update the data policy before adding a data collection SDK, account, backend, or synchronization feature.

---

[Documentation](index.md) · [README](../../README.md)
