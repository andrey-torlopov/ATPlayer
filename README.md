<p align="center">
  <img src="docs/assets/banner-en.svg" alt="ATPlayer — Press play. Just listen." width="960"/>
</p>

# ATPlayer

*[Русский](README-ru.md)*

## Why this player exists

Sometimes you have already chosen the music. You want to put your files in a playlist, press play, and leave the player alone.

ATPlayer is a simple local audio player for iPhone and iPad. Your own files, an ordered playlist, and the controls you need to listen. No account, recommendations, or streaming catalog.

<p align="center">
  <img src="docs/assets/listen-en.svg" alt="Choose your files, arrange a playlist, press play and listen." width="800"/>
</p>

## Availability

**Apple has processed version 1.0.2, build 1, and it is attached to the prepared App Store product page. App Review submission and public release are still pending.**

- iPhone and iPad with **iOS / iPadOS 26.2 or later**.
- The app interface is currently **in Russian**; documentation is available in English and Russian.
- The planned App Store release is **free, without in-app purchases**.

Developers can [run the project from source](docs/en/development.md). A source tag does not mean that Apple has approved or published that version.

## Start listening

1. In a playlist, tap **«Добавить музыку»** (Add Music) or **+**.
2. Choose your audio files or a folder in Files.
3. Tap a track. Arrange the order once, then let the music play.

The app keeps references to your files, so keep them accessible in their original location. Files in iCloud Drive may need to be downloaded first. [Quick start →](docs/en/quick-start.md)

## What is included

| For listening | For your collection |
|---|---|
| Background playback and Lock Screen controls | Files and folder import |
| Circular seek control and audio visualization | Named playlists and track reordering |
| Live Activities on supported devices | Removing entries without deleting audio |
| 10-band equalizer and preamp | JSON export of playlist information |
| Light and dark appearance; iPhone and iPad layouts | Local playlist storage; no app account |

Music is not included. Playback depends on the selected file being accessible and supported by the system audio decoder. The JSON export contains names and paths, not music or a restorable library backup. [Features and limits →](docs/en/features.md)

## Documentation

- [Quick start](docs/en/quick-start.md)
- [Features and playback behavior](docs/en/features.md)
- **[Where data lives and when a connection is needed](docs/en/data-and-privacy.md)**
- [Development and architecture](docs/en/development.md)
- [Release status and verification](docs/en/releases.md)
- [All documentation](docs/en/index.md)

## Support and privacy

[Support guide](SUPPORT.md) · [Privacy policy](PRIVACY.md) · [mail@torlopov.dev](mailto:mail@torlopov.dev)

ATPlayer does not send your library or listening history to the developer. Files selected from cloud providers use those providers' services. If you choose to email support, your message and contact details are used to handle the request.

Developed by **Andrey Torlopov**.
