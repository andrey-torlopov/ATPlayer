# Политика конфиденциальности ATPlayer / ATPlayer Privacy Policy

## Русский

Дата обновления: 1 ноября 2026 года.

Разработчик: Andrey Torlopov.

Контакт по вопросам конфиденциальности: [mail@torlopov.dev](mailto:mail@torlopov.dev).

ATPlayer предназначен для воспроизведения аудиофайлов, выбранных вами на устройстве. Для использования приложения не требуется аккаунт. Описанный ниже режим «Папки» реализован в текущих исходниках и ещё не выпущен; в отправленной сборке 1.0.2 (1) его нет.

### Какие данные использует приложение

ATPlayer хранит на устройстве названия и порядок плейлистов, сведения о выбранных треках, продолжительность, доступные обложки, ссылки и разрешения доступа к исходным файлам. Приложение также сохраняет настройки эквалайзера и сведения о последнем выбранном плейлисте. В режиме «Папки» отдельно сохраняются названия, порядок и закладки доступа только выбранных корневых каталогов. Вложенные списки, путь просмотра и очередь папки между запусками не сохраняются. Эти данные нужны для работы плеера и не отправляются разработчику.

Приложение не содержит рекламных или аналитических SDK, не использует отслеживание между приложениями и не передаёт разработчику аудиозаписи, историю прослушивания или сведения о ваших файлах.

### Доступ к аудиофайлам

Вы предоставляете доступ к отдельным файлам или выбранной папке через системное приложение «Файлы». При импорте папки в плейлист ATPlayer ищет аудиофайлы также во вложенных каталогах и сохраняет ссылки на оригиналы. Режим «Папки» читает только открытый уровень. Его аудиофайлы могут загружаться заранее и копироваться во временный локальный кеш для воспроизведения. Кеш управляется автоматически, может очищаться и не является постоянной медиатекой или гарантией офлайн-доступа.

Если выбранный файл находится в iCloud Drive, приложение может запросить его загрузку через системные средства Apple. Другие поставщики файлов также работают по своим правилам. Их сетевое взаимодействие и обработка данных регулируются условиями соответствующего поставщика, а не этой политикой.

### Системные элементы управления

ATPlayer передаёт название трека, имя исполнителя, состояние и позицию воспроизведения системным средствам Now Playing и Live Activities. Эти сведения могут отображаться на экране блокировки, в Пункте управления и на поддерживаемых системных поверхностях. Отображение зависит от устройства и его настроек.

### Экспорт и удаление

Экспорт плейлистов выполняется только по вашему действию. JSON-файл содержит названия плейлистов, названия треков, исполнителей и пути к файлам. Аудиозаписи, выбранные корни папок, их содержимое и временные очереди в экспорт не входят. Вы выбираете, где сохранить файл; при передаче другим людям или сервисам он может раскрыть перечисленные сведения.

Вы можете удалять треки, плейлисты и сохранённые ссылки на корневые папки в приложении. Удаление записей не удаляет исходные аудиофайлы. Временные копии удалённого корня освобождаются после завершения их использования плеером. Удаление приложения удаляет его локальные данные в соответствии с правилами операционной системы. Системные резервные копии и исходные файлы, хранящиеся отдельно, управляются вами через настройки устройства и соответствующие сервисы.

### Обращения в поддержку

Если вы пишете на mail@torlopov.dev, разработчик получает ваш адрес электронной почты, имя отправителя, текст сообщения и вложения, которые вы решили отправить. Эти сведения используются для ответа и разбора обращения. Это добровольная переписка; приложение не отправляет такие сведения автоматически. Доставку и хранение писем обеспечивает сервис электронной почты.

Переписка может сохраняться, пока она нужна для обработки обращения и связанной с ним поддержки. Чтобы запросить удаление переписки или задать вопрос об обработке ваших данных, напишите на тот же адрес. Необходимые для исполнения применимых требований закона сведения могут сохраняться дольше.

### Публичные страницы

Страницы поддержки и этой политики размещены на GitHub. При открытии этих страниц данные об обращении к сайту обрабатывает GitHub по своим правилам конфиденциальности.

### Изменения политики

Если способы обработки данных изменятся, эта политика будет обновлена. Дата актуальной редакции указывается в начале документа.

## English

Last updated: November 1, 2026.

Developer: Andrey Torlopov.

Privacy contact: [mail@torlopov.dev](mailto:mail@torlopov.dev).

ATPlayer plays audio files that you select on your device. No account is required to use the app. The Folders mode described below is implemented in the current source and is unreleased; it is not part of the submitted 1.0.2 (1) build.

### Data used by the app

ATPlayer stores playlist names and order, selected track information, duration, available artwork, and references and access permissions for the original files on your device. It also saves equalizer settings and the last selected playlist. Folders mode separately saves names, order, and access bookmarks for selected root directories only. Nested listings, the browsing path, and the folder queue are not saved between launches. This information supports playback and is not sent to the developer.

The app contains no advertising or analytics SDKs, does not track you across apps, and does not send the developer your audio recordings, listening history, or information about your files.

### Access to audio files

You grant access to individual files or a selected folder through the system Files picker. Importing a folder into a playlist also searches subfolders and keeps references to the originals. Folders mode reads only the open level. Its audio files may be downloaded in advance and copied into a temporary local cache for playback. The cache is managed automatically, can be cleared, and is not a permanent library or a guarantee of offline access.

If a selected file is stored in iCloud Drive, the app may request its download through Apple's system services. Other file providers also operate under their own policies. Their network activity and data practices are governed by the relevant provider's terms, not this policy.

### System playback controls

ATPlayer supplies the track title, artist name, playback status, and playback position to the system Now Playing and Live Activities features. This information may appear on the Lock Screen, in Control Center, and on supported system surfaces. Availability and display depend on your device and settings.

### Export and deletion

Playlist export happens only when you choose to export. The JSON file contains playlist names, track titles, artists, and file paths. Audio recordings, selected folder roots, their contents, and temporary queues are not included. You choose where to save the file; sharing it with other people or services may disclose this information.

You can remove tracks, playlists, and saved root-folder references in the app. Removing these entries does not delete the original audio files. Temporary copies for a removed root are released once the player stops using them. Deleting the app removes its local data according to the operating system's rules. System backups and original audio files stored separately are managed by you through device settings and the relevant services.

### Support requests

If you email mail@torlopov.dev, the developer receives your email address, sender name, message, and any attachments you choose to send. This information is used to respond to and investigate your request. This is voluntary correspondence; the app does not send this information automatically. An email service handles message delivery and storage.

Correspondence may be retained while needed to handle your request and related support. To request deletion of correspondence or ask about the handling of your information, write to the same address. Information required to meet applicable legal obligations may be retained longer.

### Public pages

The support page and this policy are hosted on GitHub. When you open these pages, GitHub handles website access data under its own privacy rules.

### Policy changes

This policy will be updated if the app's data practices change. The date of the current version appears at the start of this document.
