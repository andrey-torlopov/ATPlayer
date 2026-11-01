# App Review Notes — ATPlayer 1.1.0 (2)

## Notes to paste into App Store Connect

ATPlayer is a player for the user's own DRM-free audio on iPhone and iPad. No account, sign-in, subscription, or developer backend is required. It contains no ads, tracking, or usage-analytics SDKs and sends no library or listening data to the developer. It does not provide a music catalog or download music from websites. Local files play offline; iCloud Drive, network shares, and other Files providers may need a network connection to list directories or obtain audio.

The interface is in Russian. Review steps:
1. Extract the existing ATPlayer-Review-Demo.zip attachment in Files. It contains an original CC0 audio file, Morning-Light.wav, whose metadata title is “Утренний свет”. The demo is for review only and is not bundled with the app.
2. Open ATPlayer in “Плейлисты” (Playlists). In the empty “My Music” playlist, tap “Добавить музыку” (Add Music). For a populated playlist, open its ellipsis menu and choose “Добавить треки” (Add Tracks). Select the WAV, then tap the imported track to play.
3. The large central button pauses/resumes; side buttons select previous/next. Drag the circular progress ring to seek. The mode button below Settings cycles normal order, playlist/folder repeat, shuffle, and single-track repeat.
4. Tap the plus beside the Playlists heading to create a second playlist. The up/down-arrows button beside that heading opens “Порядок плейлистов” (Playlist Order); drag the right-hand handles. For track ordering/removal, use the playlist ellipsis menu, “Редактировать треки” (Edit Tracks). Ordering is saved immediately and does not restart audio.
5. Select “Папки” (Folders), tap “Добавить папку” (Add Folder), and choose the extracted demo directory. Open it and tap Morning-Light.wav. The app copies current-level audio into a temporary local cache before playback and prepares other audio in that level in the background. Selecting a track takes priority.
6. Only audio in the open directory enters its queue; subfolders are not added to playback. Navigating or switching Playlists/Folders leaves current audio playing. Root-folder access bookmarks survive relaunch; expanded paths, nested listings, and folder queues do not. Metadata scans may inspect descendants to hide branches without supported audio, but do not download their audio for that scan. Importing a folder into a playlist is a separate, recursive import operation.
7. Return Home or lock the device to test intentional background audio and system Now Playing controls. Live Activities depend on device support and settings. The top-right sliders button opens Settings; “Эквалайзер” opens the 10-band equalizer and preamp.

Removing playlist/track entries or a saved folder reference never deletes source audio. Folder cache files are disposable; active audio copies remain until the player releases them. Playlist import stores references to originals. JSON export includes names and paths, not audio or folder queues. Keep originals available for playlist playback. The attached ZIP's README describes the earlier playlist flow; these notes include the new 1.1.0 folder and ordering controls.

## Release operator notes — do not paste

- Target version/build: 1.1.0 (2). These notes do not assert approval or publication.
- Reuse the unchanged attachment at `Artifacts/AppStore-2026-11-01/review-attachment/ATPlayer-Review-Demo.zip`. Do not regenerate the audio or its ZIP for this release.
- Confirm that the existing attachment is present on the actual 1.1.0 review record; its attachment state is not established by this file.
- Keep the account owner's existing App Review contact details. No contact name, phone, or email was invented.
- “Sign-in required” remains off. No credentials are required for the local demo.
- The interface is Russian despite the English product-page localization.
- Real iCloud/SMB/provider behavior depends on source availability, permissions, and the provider. Local cache and playback integration are tested; this text does not claim a successful physical-device/provider test.
- Metadata limits were checked against [Apple platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information). Keywords are conservatively checked against both 100 characters and 100 UTF-8 bytes; pasted review notes are checked against 4000 UTF-8 bytes.
