# ATPlayer — подготовка App Store 1.0

Дата: 1 ноября 2026 года, Europe/Moscow.

Статус: подготовка остановлена на данных владельца и соглашении Apple. Приложение **не опубликовано**, новая карточка **не создана**, бинарник **не загружен**, отправки в App Review **не было**. Свежие скриншоты пока не сняты. Сборки, архивирование и тесты с компиляцией не запускались: отдельное разрешение по CORE.md, п. 9, запрошено и ещё не получено.

## Позиционирование

**ATPlayer — локальная музыка без суеты.**

Включил и слушай. Добавьте свои аудиофайлы, соберите плейлист в нужном порядке и нажмите Play. Для тех, кто хочет слушать любимое, а не выбирать следующий трек каждую минуту.

## Подготовленные материалы

- [Русская карточка](metadata/ru-RU.md), [точные поля JSON](metadata/ru-RU.json).
- [Английская карточка](metadata/en-US.md), [точные поля JSON](metadata/en-US.json). Английский текст карточки не означает английскую локализацию интерфейса.
- [App Review Notes](metadata/review-notes.md).
- [Тексты и план скриншотов](metadata/screenshot-copy.md).
- [Черновик политики конфиденциальности](metadata/privacy-policy.md); для публикации нужны подтверждённый контакт и рабочий публичный URL.
- [Проверка ограничений текстовых полей](metadata/validation.json).
- [Оригинальные демо-аудиофайлы CC0](demo-audio/README.md), [проверка WAV](demo-audio/verification.json). Эти файлы предназначены для снимков интерфейса и App Review, не включены в приложение.
- [Настройки локального экспорта архива](ExportOptions.plist), без автоматической загрузки.

## Подтверждённый preflight

| Параметр | Результат |
| --- | --- |
| Исходный HEAD до подготовки | `26588c4388e85d3701337d03d988f337b5b792aa` |
| Bundle ID приложения | `dev.torlopov.atplayer.ios` |
| Bundle ID расширения | `dev.torlopov.atplayer.ios.extension` |
| Team | `79798GRSHW` |
| Версия / build | `1.0` / `1` |
| Платформы | iPhone и iPad, iOS/iPadOS 26.2+ |
| Интерфейс | Русский |
| Xcode на машине | 27.2, build 27B52; проверено `xcodebuild -version`, без сборки |
| Профили | `ATPlayer iOS App Store`, `ATPlayer iOS Extension App Store` |
| Срок профилей | До 1 ноября 2027 года; bundle IDs и team совпадают |
| Distribution identity | `Apple Distribution: Andrey Torlopov (79798GRSHW)` доступен |
| Иконки | Три варианта 1024 × 1024, без alpha |
| Сторонние SDK | Не обнаружены в исходниках и package dependencies |
| Сбор данных | По исходникам нет аналитики, рекламы, tracking, аккаунтов и передачи данных разработчику; кандидат декларации `Data Not Collected` проверяется повторно по финальному архиву |

Существующая карточка [Torlopov.App.One](https://appstoreconnect.apple.com/apps/6744414249/distribution/info) имеет другой Bundle ID — `torlopov.app.one`. Её поля не менялись. Для ATPlayer нужна отдельная карточка.

Попытка открыть New App в App Store Connect получила **Agreement Update: “Your paid application agreement is outdated.”** Карточка не была создана. В Business наблюдались Free Apps Agreement — Active; Paid Apps Agreement — Pending (New Agreement Available). Владелец должен разобраться с актуальными условиями; соглашения не принимались агентом. Раздел [Business](https://appstoreconnect.apple.com/business) оставлен открытым в Safari.

## Изменения проекта

- `SRC/ATPlayer/ATPlayer/PrivacyInfo.xcprivacy`: own UserDefaults — `CA92.1`; SystemBootTime для интервалов — `35F9.1`; tracking выключен, collected data types пусты.
- `SRC/ATPlayer/ATPlayer/Info.plist`: русский язык и `ITSAppUsesNonExemptEncryption=false`, по проверенному отсутствию собственной криптографии.
- `SRC/ATPlayer/ATPlayer.xcodeproj/project.pbxproj`: development region `ru` вместо `en`.

Swift-код не менялся. Исходное пользовательское изменение `UserInterfaceState.xcuserstate` сохранено. Commit и push не выполнялись.

## Что требуется от владельца

1. Принять актуальное соглашение Apple, блокирующее New App.
2. Явно разрешить Release-сборку, архив и симуляторы. Это ограничение действующего CORE.md, п. 9, а не дополнительное требование Apple.
3. Выбрать цену: бесплатно либо указанная владельцем платная цена.
4. Указать публичный контакт поддержки, отдельные телефон/email для Apple App Review и место публикации support/privacy страниц. Контакты не подставлялись из посторонних источников.

## Следующие действия после ответов

1. Опубликовать подтверждённую политику и страницу поддержки; проверить HTTPS без авторизации. Добавить доступ к политике из Settings приложения.
2. Создать ATPlayer в App Store Connect: iOS, Russian, Bundle ID `dev.torlopov.atplayer.ios`, SKU `ATPLAYER-IOS-001`, категория Music. Имя пока не проверено на доступность.
3. Собрать текущие исходники для симулятора и снять реальные экраны iPhone и iPad с оригинальными demo WAV. Проверить размер, отсутствие alpha, отсутствие персональных данных и соответствие интерфейсу релиза. Старые снимки из `Task/Redisign/Verification` не считать материалами текущего релиза.
4. Собрать подписанный archive, проверить bundle IDs, version/build, языки, подпись, embedded profiles, privacy manifest, icon и extension. Экспортировать локально с `ExportOptions.plist`.
5. Загрузить бинарник в App Store Connect, дождаться processing, проверить предупреждения и выбрать build.
6. Заполнить тексты, screenshots, App Privacy, age rating, content rights, export compliance, review contacts, цену/регионы. Отключить Sign-in required. Использовать только подтверждённые декларации.
7. Проверить всю карточку и отправить на App Review в рамках запроса владельца о публикации. Результат проверки и дата доступности зависят от Apple; статус submission не равен опубликованному приложению.

## Команды для следующего этапа — ещё не выполнялись

Из корня репозитория, только после явного разрешения сборки и завершения policy:

```sh
xcodebuild -project SRC/ATPlayer/ATPlayer.xcodeproj -scheme ATPlayer -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/ATPlayer-AppStore-Simulator CODE_SIGNING_ALLOWED=NO build

xcodebuild -project SRC/ATPlayer/ATPlayer.xcodeproj -scheme ATPlayer -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/ATPlayer-AppStore-Archive -archivePath Artifacts/AppStore-2026-11-01/ATPlayer.xcarchive archive

xcodebuild -exportArchive -archivePath Artifacts/AppStore-2026-11-01/ATPlayer.xcarchive -exportPath Artifacts/AppStore-2026-11-01/export -exportOptionsPlist Artifacts/AppStore-2026-11-01/ExportOptions.plist
```

Сборки должны сохранить логи в этой папке. Не использовать старое `SRC/ATPlayer/build/Release-iphonesimulator/ATPlayer.app`: проверенный Bundle ID там `torlopov.atplayer`, SDK `iphonesimulator26.2`; это устаревший артефакт.

## Откат и проверка

Публичного релиза ATPlayer в текущей карточке ещё нет; last known good опубликованной версии отсутствует. До submission карточка редактируется. После submission запрос можно снять с проверки. После публикации бинарник заменяется новой версией; быстрое возвращение старого бинарника не гарантировано. Удаление из продажи не откатывает установки пользователей. Миграции данных в подготовленных изменениях нет.

Локальные проверки: `plutil -lint` для изменённых plist/project/manifest, Python-проверка размеров текстовых полей и WAV, `git diff --check`. Финальная сборка, launch, screenshot QA и App Store validation ещё не выполнены.

## Источники Apple

- [Создание карточки](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/).
- [Требования к скриншотам](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).
- [Загрузка скриншотов](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/).
- [App Review Guidelines, включая privacy policy и реальные screenshots](https://developer.apple.com/app-store/review/guidelines/).
- [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/).
- [Required-reason API categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
- [Encryption key](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption).
