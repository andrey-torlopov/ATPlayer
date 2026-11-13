# Поддержка ATPlayer / ATPlayer Support

## Русский

**Включил и слушай.** ATPlayer — простой плеер для ваших локальных аудиофайлов на iPhone и iPad.

Разработчик: Andrey Torlopov. По вопросам работы приложения пишите на [mail@torlopov.dev](mailto:mail@torlopov.dev).

### Начало работы

1. Откройте ATPlayer. В пустом плейлисте нажмите **«Добавить музыку»** или кнопку **+** внутри плейлиста.
2. Выберите свои аудиофайлы или папку в системном приложении «Файлы».
3. Нажмите на трек, чтобы начать воспроизведение. Кнопка в центре ставит воспроизведение на паузу и продолжает его; кнопки по бокам переключают треки.
4. Для перемотки проведите по круглому индикатору воспроизведения.

Музыка в приложение не включена. Для прослушивания нужны ваши аудиофайлы. Импорт папки в плейлист включает её вложенные каталоги.

### Папки — кандидат 1.1.0

Переключите **«Плейлисты / Папки»** в режим **«Папки»**, нажмите **«Добавить папку»** и выберите корневой каталог. Каждый открытый уровень показывает только непосредственные папки и аудиофайлы. Нажатие аудиофайла создаёт очередь этого уровня без обхода вложенных папок. Навигация и переключение режима не меняют уже играющую очередь.

После перезапуска сохраняются только выбранные корни; путь, списки и очередь папки создаются заново. **«Обновить папку»** обновляет список. Удаление корня из ATPlayer сохраняет оригиналы, но останавливает его текущую очередь. Функция входит в **1.1.0 (2)**, отправленную на App Review со статусом **Waiting for Review**; публичный выпуск ещё не выполнен. Актуальное состояние — в [статусе релиза](docs/ru/releases.md).

### Плейлисты и настройки

Кнопка **+** рядом с заголовком «Плейлисты» создаёт новый плейлист. В версии 1.1.0 кнопка со стрелками вверх/вниз рядом с заголовком открывает **«Порядок плейлистов»**: перетаскивайте списки за правые ручки, порядок сохраняется сразу. В меню **…** нужного плейлиста можно переименовать его, отредактировать порядок треков или удалить список. Удаление записей не удаляет исходные аудиофайлы.

Кнопка с ползунками в правом верхнем углу открывает настройки. В разделе **«Эквалайзер»** доступны 10 полос и предусиление. Изменения применяются сразу и сохраняются автоматически.

### Файл не воспроизводится

Проверьте, что исходный файл существует и открывается через «Файлы». Плейлисты хранят ссылки на оригиналы. В режиме «Папки» версии 1.1.0 плеер дополнительно подготавливает аудио открытого уровня во временном локальном кеше. Если вы переместили или удалили файл, обновите папку или выберите источник заново.

Для iCloud Drive и сетевых поставщиков может потребоваться загрузка по сети. Кеш папок очищается и не гарантирует офлайн-доступ; отметка «Подготовлен» означает завершённую подготовку, а не постоянное хранение. Если файл доступен, но ошибка сохраняется, попробуйте другой аудиофайл, например MP3 или WAV без DRM.

### Фоновое воспроизведение

Начните воспроизведение и сверните приложение или заблокируйте экран. Управление доступно через системные элементы воспроизведения. Live Activities отображаются на поддерживаемых устройствах, если разрешены в настройках системы.

### Экспорт плейлистов

В настройках выберите **«Экспорт плейлистов»**. JSON-файл содержит названия плейлистов, треков, исполнителей и пути к файлам. Аудиофайлы, сохранённые корни папок и временные очереди в него не входят. Экспорт не является резервной копией музыки и не предназначен для восстановления медиатеки в приложении.

### Сообщить о проблеме

В письме укажите версию ATPlayer, модель устройства, версию iOS или iPadOS, последовательность действий и текст ошибки. Если проблема связана с файлом, укажите его формат и место хранения: на устройстве, в iCloud Drive или у другого поставщика файлов. Скриншот можно приложить по желанию.

Не требуется отправлять вашу музыкальную библиотеку. Переписка и вложения, которые вы отправляете добровольно, используются для ответа и разбора обращения. Подробнее — в [политике конфиденциальности](https://github.com/andrey-torlopov/ATPlayer/blob/main/PRIVACY.md).

## English

**Press play. Just listen.** ATPlayer is a simple player for your local audio files on iPhone and iPad. The current app interface is in Russian.

Developer: Andrey Torlopov. For help with the app, email [mail@torlopov.dev](mailto:mail@torlopov.dev).

### Getting started

1. Open ATPlayer. In an empty playlist, tap **«Добавить музыку»** (Add Music) or the **+** button inside the playlist.
2. Select your audio files or a folder in the system Files picker.
3. Tap a track to start playing. The central button pauses and resumes playback; the buttons on either side select the previous and next tracks.
4. Drag around the circular playback indicator to seek.

Music is not included. Bring your own audio files. Importing a folder into a playlist includes its subfolders.

### Folders — 1.1.0 candidate

Switch **«Плейлисты / Папки»** (Playlists / Folders) to **«Папки»**, tap **«Добавить папку»** (Add Folder), and choose a root directory. Each level shows only its immediate folders and audio files. Tapping audio creates a queue for that level without traversing subfolders. Browsing and switching modes leave the active queue playing.

Only selected roots survive relaunch; the browsing path, listings, and folder queue start fresh. **«Обновить папку»** (Refresh Folder) refreshes the listing. Removing a root from ATPlayer keeps the originals but stops its active queue. The feature is included in **1.1.0 (2)**, submitted to App Review with **Waiting for Review** status; public release is still pending. See [release status](docs/en/releases.md) for the latest recorded state.

### Playlists and settings

The **+** button beside **«Плейлисты»** (Playlists) creates a new playlist. In version 1.1.0, the up/down arrows beside the heading open **«Порядок плейлистов»** (Playlist Order): drag the handles on the right; the order saves immediately. The playlist **…** menu lets you rename it, edit the track order, or delete the list. Removing entries does not delete the original audio files.

The sliders button at the top right opens settings. **«Эквалайзер»** (Equalizer) provides 10 bands and a preamp. Changes apply immediately and are saved automatically.

### A file will not play

Check that the original file still exists and opens in Files. Playlists keep references to the originals. Folders mode in version 1.1.0 also prepares audio from the open level in a temporary local cache. If you moved or deleted a file, refresh the folder or select the source again.

iCloud Drive and network providers may need a connection to download files. The folder cache can be cleared and does not guarantee offline access; «Подготовлен» (Prepared) records successful preparation, not permanent storage. If the file is available but the error continues, try another audio file, such as a non-DRM MP3 or WAV.

### Background playback

Start playback, then leave the app or lock your device. Playback is available through the system media controls. Live Activities appear on supported devices when allowed in system settings.

### Playlist export

In settings, choose **«Экспорт плейлистов»** (Export Playlists). The JSON file contains playlist names, track titles, artists, and file paths. It does not include audio files, saved folder roots, or temporary queues. The export is not a music backup and is not intended to restore the library in the app.

### Report a problem

Include your ATPlayer version, device model, iOS or iPadOS version, steps to reproduce the problem, and the error message. For a file-related problem, include the file format and whether it is stored on the device, in iCloud Drive, or with another file provider. A screenshot is optional.

You do not need to send your music library. Correspondence and attachments that you choose to send are used to respond to and investigate your request. See the [privacy policy](https://github.com/andrey-torlopov/ATPlayer/blob/main/PRIVACY.md) for details.
