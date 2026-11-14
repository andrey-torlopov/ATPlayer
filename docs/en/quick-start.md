# Quick start

*[Русский](../ru/quick-start.md)*

These steps apply to an installed copy of ATPlayer on iOS or iPadOS 26.0 or later. For version availability, see [release status](releases.md). Developers can use the [source setup](development.md).

## 1. Add your files

On first launch, ATPlayer creates a playlist named **My Music**. Tap **«Добавить музыку»** (Add Music) in the empty playlist, or open its **…** menu and select **«Добавить треки»** (Add Tracks). Select audio files or a folder through Files. Folder import also looks in subfolders.

For a first check, use a local non-DRM MP3 or WAV. When selecting files from iCloud Drive, allow them to finish downloading. Playlist import remembers access to the original files rather than creating a permanent audio library.

## 2. Press play

Tap a track to begin. The large central button pauses and resumes playback. The side buttons move to the previous and next tracks. Drag around the circular progress ring to seek.

In normal playlist playback, the player follows the stored track order. If you have several playlists, the playback sequence continues through them in their displayed order. It stops at the end of the full sequence.

## 3. Set up a playlist once

Use **+** beside **«Плейлисты»** (Playlists) to create another playlist. Open its **…** menu and select **«Редактировать треки»** (Edit Tracks). Drag the handles on the right to reorder tracks; the order saves automatically. Select several tracks to remove them together. Removing entries leaves the original files intact.

The up/down arrows beside **«Плейлисты»** open playlist reordering. Drag a playlist by its right-hand handle and tap **«Готово»** (Done); order saves automatically.

## 4. Keep listening

Leave the app or lock the device while playback is running. Use the system playback controls to pause, resume, and switch tracks. Live Activities depend on device support and system settings.

The sliders button at the top right opens settings. **«Эквалайзер»** (Equalizer) adjusts the 10 frequency bands and preamp. Changes apply immediately.

If a file becomes unavailable after you move it or change providers, select it again. See [data and privacy](data-and-privacy.md) and [support](../../SUPPORT.md).

## Try radio in 1.5.0

Radio is off by default. In Settings → **Radio**, raise **Radio effect** to add interference. Use **Radio effect background** for a continuous background, or leave it at 0 to allow quiet intervals. The background is linked to the main level and cannot exceed it. Set the main level to 0 for clean playback. [Control behavior →](features.md#radio-effect-in-150)

## Listen directly from folders

Above the library, choose **«Папки»** (Folders), then **«Добавить папку»** (Add Folder). Select a root directory through Files. Open subfolders one at a time; each screen shows only that level’s folders and audio.

Folders without supported music are hidden; paths to music deeper in the tree remain visible. Selecting an empty root does not add it. Checking a large network tree can take time.

Tap a file to play the audio at that level only. Subfolders are not included. Moving around the browser or switching back to Playlists keeps the active queue playing. Use the back arrow to move up and **«Обновить папку»** (Refresh Folder) after external changes.

Files are prepared in a temporary local cache. iCloud and network sources may need a connection; the cache is not a permanent offline copy. Only root references are saved across launches. Removing a root from ATPlayer keeps the original files and stops playback from that root. [Cache and data details →](data-and-privacy.md)

---

[Documentation](index.md) · [README](../../README.md)
