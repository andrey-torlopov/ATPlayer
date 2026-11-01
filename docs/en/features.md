# Features and playback behavior

*[Русский](../ru/features.md)*

## A playlist you control

Create and rename playlists, add files or folders, change track order, and remove one or several entries. The app stores your chosen order locally. Removing a playlist or track entry does not delete the audio file.

The player reads titles, artist names, duration, and available artwork from audio metadata. When a title is missing, it uses the file name. Folder import includes subfolders and sorts discovered file paths naturally before adding them.

## Playback

The main screen has play/pause, previous/next, and circular seeking. The radial visualization reacts to the audio. Playback proceeds through tracks and then through subsequent playlists in the displayed order. There is no shuffle or repeat control in this version. Unavailable files can be skipped while the player looks for the next playable track.

Background playback uses the system audio session. Track information and controls appear through Now Playing. Live Activities provide another system surface on supported devices when enabled. The app is not a general-purpose Home Screen widget collection.

## Sound and appearance

The equalizer provides 10 frequency bands and preamp controls. Each gain is adjustable from −12 to +12 dB. Changes apply immediately and persist between launches; **«Сбросить настройки»** resets the equalizer.

The interface follows the system's light or dark appearance and adapts to iPhone, iPad, orientation, and larger text sizes. Controls include VoiceOver labels and accessible seeking. This is implemented behavior, not a claim of a completed accessibility certification.

## Files and export

The system file picker accepts audio and folders. MP3 and WAV are useful starting formats. Actual playback is performed by AVFoundation and depends on the codec, file contents, and file access; a file extension alone is not a compatibility guarantee. DRM-protected streaming downloads are not a supported music source.

JSON export saves playlist names and each track's artist, title, and file path. It does not contain audio, access bookmarks, or a complete library database. The app has no corresponding JSON restore feature.

## Scope

ATPlayer has no account, recommendations, streaming catalog, music downloader, or in-app purchase flow. The interface is Russian. There is no English UI localization, cross-device playlist synchronization, sleep timer, or CarPlay-specific interface in this version.

For offline listening, the original files must remain available locally. [Data and privacy](data-and-privacy.md) explains the difference between a playlist reference and a copy of the audio.

---

[Documentation](index.md) · [README](../../README.md)
