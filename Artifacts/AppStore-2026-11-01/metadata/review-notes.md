# App Review Notes

## Notes to paste into App Store Connect

ATPlayer is a local audio player for iPhone and iPad. No account, sign-in, subscription, or server connection is required. The app does not provide a music catalog or download music from websites. Users select their own audio files through the system Files picker.

The app interface is in Russian. To review playback:
1. Make a non-DRM audio file, such as an MP3 or WAV, available in Files on the device. Download it locally first if it is stored in iCloud Drive.
2. Launch ATPlayer. The default playlist is named “My Music”. Tap the plus button inside that playlist, or the “Добавить музыку” (Add Music) button in its empty state, and select the audio file.
3. Tap the imported track to start playback. The large central button pauses or resumes playback; the buttons on either side select the previous and next tracks. Drag around the circular progress control to seek.
4. Background audio is intentional: return to the Home Screen or lock the device while audio is playing. Playback controls and track information are provided through the system Now Playing interface. Live Activities are also available when supported and enabled on the device.
5. To review sound settings, tap the sliders button at the top right, then “Эквалайзер” (Equalizer). The 10 bands and preamp apply immediately and are saved locally.
6. To reorder tracks, open the playlist ellipsis menu and choose “Редактировать треки” (Edit Tracks).

The app saves file references, playlist metadata, and settings locally. It does not copy the selected audio into its own library. Removing a playlist or track entry does not delete the original audio file. The JSON playlist export contains names and file paths, not audio files, and is not a library restore feature.

The attached ATPlayer-Review-Demo.zip contains an original CC0 WAV and review instructions. Unzip it in Files and import Morning-Light.wav; its displayed track title is “Утренний свет”.

## Release operator notes — do not paste

- Confirm the final build's empty-state button wording before submission. At preparation time the source UI uses “Добавить музыку”.
- App Review contact name, email, and phone must come from the account owner; no contact details have been invented.
- “Sign-in required” should be off for the reviewed implementation.
- The interface is Russian even when an English product-page localization is used.
- ATPlayer-Review-Demo.zip was uploaded to App Review Information. On November 1, 2026 at 17:20 Moscow time, the main agent observed its filename without a Processing indicator in App Store Connect. The attachment paragraph above was appended to the saved review notes. This does not mean the app has been submitted for review.
