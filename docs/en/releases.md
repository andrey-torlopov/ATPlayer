# Release status and verification

*[Русский](../ru/releases.md)*

Status recorded on **November 1, 2026**.

## Working changes — unreleased

One button below Settings cycles through playlist repeat → shuffle → repeat one → normal playback. The modes are mutually exclusive, and the button icon shows the selected mode. See [playback behavior](features.md#playback). These changes remain local; the version and build numbers are unchanged, and no new build has been uploaded to App Store Connect. They are not part of the previously submitted 1.0.2 (1) build. Folder browsing and playlist reordering are still at the analysis stage.

## App Store candidate

**Version 1.0.2, build 1** was submitted to App Review on November 1, 2026 at **17:28 Moscow time**. App Store Connect shows **Waiting for Review** for the submitted app version. Automatic release after approval is enabled. The app is not yet publicly available on the App Store; submission does not mean Apple has approved it.

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

The owner has reported successful manual testing of the app. That report is not a complete device, file-format, accessibility, or audio-route test matrix. Current release preparation also verified the bundle versions, device families, privacy manifest, and distribution signatures. These checks establish packaging facts; they do not guarantee App Review approval.

## Runtime checks that matter

For a playback change, cover local file import and access after relaunch, play/pause and seeking, track completion, an unavailable file, playlist changes, and background operation. For system integration changes, also check interruptions, connected audio devices, Lock Screen controls, and Live Activities on supported hardware.

For file-provider changes, test a downloaded local file and an iCloud file separately. The player stores references rather than copies, so provider behavior is part of the scenario. Avoid inferring codec coverage from filename extensions alone.

## Updating documentation

When Apple makes the app publicly available, replace the preparation status with the verified App Store link and release date. Do not add a download badge while the listing is only a draft, in review, or available to private testers.

Keep [privacy](../../PRIVACY.md) and [support](../../SUPPORT.md) current with the shipped app. Update the data policy before adding a data collection SDK, account, backend, or synchronization feature.

---

[Documentation](index.md) · [README](../../README.md)
