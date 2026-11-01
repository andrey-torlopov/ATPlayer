# Features and playback behavior

*[Русский](../ru/features.md)*

## A playlist you control

Create and rename playlists, add files or folders, change track order, and remove one or several entries. The app stores your chosen order locally. Removing a playlist or track entry does not delete the audio file.

The player reads titles, artist names, duration, and available artwork from audio metadata. When a title is missing, it uses the file name. Folder import includes subfolders and sorts discovered file paths naturally before adding them.

## Folders in the current source

**Unreleased; not included in the submitted 1.0.2 (1) build.** The **«Плейлисты / Папки»** switch changes the library area. In **«Папки»**, add a root through Files and open it to see only its immediate subfolders and supported audio files. Folders appear first; names use natural sorting. Refresh reads the open level again.

Tapping audio creates an in-memory queue containing only the audio files at that level, in displayed order. It never descends into subfolders or continues into another folder or playlist. Repeat, shuffle, and repeat-one apply to that active folder queue. Without repeat, playback stops at its end. Browsing elsewhere or switching library modes does not change the active track or queue; selecting another file does.

Only selected roots survive relaunch. Nested folders, listings, the browsing path, and the folder queue are not restored. Removing a root forgets its reference and stops its active queue; it does not delete source files. Folder entries do not become playlist records.

Audio at the open level is prepared sequentially in a temporary local cache, including files from iCloud or network providers. Explicit playback has priority. The cache has a **512 MiB soft budget**: in-use files are protected, and an explicitly selected large recording or a track handoff may temporarily exceed the budget. Unused copies are evicted. This is not an offline-download feature; «Подготовлен» means preparation succeeded, not that the copy will be kept permanently.

## Playback

The main screen has play/pause, previous/next, and circular seeking. The radial visualization reacts to the audio. In Playlists mode, default playback proceeds through tracks and then through subsequent playlists in the displayed order. Unavailable files can be skipped while the player looks for the next playable track.

**The working version, not yet submitted to the App Store**, adds one mode button directly below Settings. Each tap changes its icon and advances through **playlist repeat → shuffle → repeat one → normal playback**, then starts the cycle again. Only one mode is active at a time.

- **Playlist repeat** loops the current playlist in its saved order.
- **Shuffle** mixes the current playlist without changing its saved order. Tracks do not repeat within a pass, and Previous follows the same queue backwards. Playback stops at the end of that queue.
- **Repeat one** restarts the current track when it ends; manual Previous and Next still change tracks within the current playlist.
- **Normal playback** is shown by a right arrow. It plays tracks and subsequent playlists sequentially, with shuffle and repeat disabled.

The selected mode persists between launches. Selecting a track from another playlist changes the playback scope; shuffle starts a new queue with that track. The mode button does not change the saved playlist or track order. The submitted **1.0.2 (1)** build does not contain this button.

Background playback uses the system audio session. Track information and controls appear through Now Playing. Live Activities provide another system surface on supported devices when enabled. The app is not a general-purpose Home Screen widget collection.

## Sound and appearance

The equalizer provides 10 frequency bands and preamp controls. Each gain is adjustable from −12 to +12 dB. Changes apply immediately and persist between launches; **«Сбросить настройки»** resets the equalizer.

The interface follows the system's light or dark appearance and adapts to iPhone, iPad, orientation, and larger text sizes. Controls include VoiceOver labels and accessible seeking. This is implemented behavior, not a claim of a completed accessibility certification.

## Files and export

The system file picker accepts audio and folders. MP3 and WAV are useful starting formats. Actual playback is performed by AVFoundation and depends on the codec, file contents, and file access; a file extension alone is not a compatibility guarantee. DRM-protected streaming downloads are not a supported music source.

JSON export saves playlist names and each track's artist, title, and file path. It does not contain audio, access bookmarks, saved folder roots or folder queues, or a complete library database. The app has no corresponding JSON restore feature.

## Scope

ATPlayer has no account, recommendations, streaming catalog, music downloader, or in-app purchase flow. The interface is Russian. There is no English UI localization, cross-device playlist synchronization, sleep timer, or CarPlay-specific interface in this version.

For reliable offline listening, keep the original files available locally; temporary folder caching does not guarantee offline access. [Data and privacy](data-and-privacy.md) explains the difference between a playlist reference and a copy of the audio.

---

[Documentation](index.md) · [README](../../README.md)
