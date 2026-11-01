# Data, files, and privacy

*[Русский](../ru/data-and-privacy.md)*

## The playlist is not a copy of your music

When you select audio, ATPlayer stores track metadata and file-access bookmarks. The original audio stays in the location you selected through Files. A selected folder also provides access for tracks found within it.

This keeps the app's role simple, but access to the original file matters. Moving it, deleting it, changing its provider, or making it unavailable can stop playback. Select it again through Files if access needs to be restored.

## What is stored on the device

| Data | Purpose |
|---|---|
| Playlist names, order, and track membership | Reopen your collection in the chosen order |
| Titles, artists, duration, available artwork | Present the selected audio |
| Original paths and access bookmarks | Locate and read the files you chose |
| Equalizer settings and last played playlist | Preserve sound preferences and playlist presentation |

Playlist data uses SwiftData; settings use UserDefaults. The app does not provide its own cloud synchronization or server. System backups are governed by your device and account settings.

## When a connection is used

Available local files can play without an internet connection. iCloud Drive files may need downloading, and other file providers may use their own networks. ATPlayer's file references do not guarantee that a provider will keep a file downloaded forever.

Opening the privacy policy takes you to its public GitHub page. Choosing support opens an email link. GitHub, your email provider, and any file provider have their own data practices.

## Playback information

Now Playing and Live Activities receive track information and playback state for the system's playback surfaces. The information can be visible on the Lock Screen and Control Center according to system settings.

## Export and deletion

The JSON export contains playlist and track names, artists, and paths. It contains no audio and cannot restore the library in ATPlayer. Choose where to save or share it, bearing in mind that paths and titles can reveal information about your collection.

Deleting entries in ATPlayer leaves the audio files intact. Deleting the app removes its local data according to the operating system's rules; original files and system backups are managed separately.

The app has no advertising, analytics SDK, or automatic transmission of your library to the developer. If you email support, the developer receives the contact details, message, and attachments you voluntarily provide for handling your request.

The full [privacy policy](../../PRIVACY.md) explains these practices and gives the privacy contact.

---

[Documentation](index.md) · [README](../../README.md)
