# Winamp iOS (SwiftUI + SwiftData)

Приложение повторяет логику классического Winamp:
- ландшафт: основной плеер + анимированный эквалайзер + плейлист;
- нажатие на эквалайзер открывает отдельное окно эквалайзера push-навигацией;
- портрет: плеер + плейлист, без встроенного эквалайзера;
- плейлист можно развернуть на весь экран, плеер сворачивается до 3 кнопок.

Песни добавляются из Files. Приложение сохраняет security-scoped bookmark в SwiftData и потом читает аудио напрямую по сохраненному пути/закладке.

## Архитектура

- `Models/TrackItem.swift` - модель SwiftData для трека.
- `Services/AudioPlaybackService.swift` - AVAudioEngine, AVAudioPlayerNode, AVAudioUnitEQ и визуализатор.
- `Services/PlaylistStorageService.swift` - операции чтения/добавления/удаления плейлиста в SwiftData.
- `ViewModels/WinampViewModel.swift` - orchestration слоя UI и сервисов.
- `Views/*` - отдельные экраны и компоненты (плеер, плейлист, эквалайзер).

## Как включить фоновое воспроизведение

В проекте уже добавлен `UIBackgroundModes = audio` через build settings (`INFOPLIST_KEY_UIBackgroundModes`).

Проверьте в Xcode:
1. Откройте Target `Winamp`.
2. `Signing & Capabilities`.
3. Добавьте capability **Background Modes**.
4. Включите пункт **Audio, AirPlay, and Picture in Picture**.

Дополнительно (уже реализовано в коде):
- `AVAudioSession` переведен в категорию `.playback`, чтобы аудио не останавливалось при уходе в фон.

## Сборка

```bash
xcodebuild -project SRC/Winamp/Winamp.xcodeproj -scheme Winamp -destination 'generic/platform=iOS Simulator' build
```
