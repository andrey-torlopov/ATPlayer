# ATPlayer — App Store 1.0.2 (1)

Дата: 1 ноября 2026 года, Europe/Moscow.

**Статус: версия 1.0.2 (1) отправлена на App Review 1 ноября 2026 года в 17:28 MSK. App Store Connect показывает Waiting for Review; в submission один item, черновиков нет. Включён автоматический выпуск после одобрения. Приложение ещё не опубликовано в App Store.**

Карточка: [ATPlayer, app ID 6829444190](https://appstoreconnect.apple.com/apps/6829444190/distribution). Upload завершён **1 ноября 2026 года в 16:39:57 MSK**. Состояние upload log **Uploaded package is processing** было промежуточным: последующая проверка основным агентом в App Store Connect подтвердила завершение обработки и выбор build **1.0.2 (1)** в карточке.

Этот файл фиксирует завершённые этапы. Последующие действия в App Store Connect подтверждены основным агентом в текущем чате. [submission-result.json](submission-result.json) фиксирует подтверждённую финальную отправку; upload-result.json сохраняет историческое состояние именно на момент загрузки.

## Позиционирование

**ATPlayer — локальная музыка без суеты.**

Включил и слушай. Добавьте свои аудиофайлы, соберите плейлист в нужном порядке и нажмите Play. Для тех, кто хочет слушать любимое, а не выбирать следующий трек каждую минуту.

## Подготовленные и опубликованные материалы

- [Русская карточка](metadata/ru-RU.md), [точные поля JSON](metadata/ru-RU.json).
- [Английская карточка](metadata/en-US.md), [точные поля JSON](metadata/en-US.json). Английский текст карточки не означает английскую локализацию интерфейса.
- [App Review Notes](metadata/review-notes.md).
- [Тексты и план скриншотов](metadata/screenshot-copy.md), [текущий отчёт проверки скриншотов](screenshots/verification.json).
- [Header / Search Results asset](creative-assets/header-universal.png), [описание](creative-assets/README.md), [техническая проверка и подтверждённые размещения ASC](creative-assets/verification.json).
- Опубликованная [политика конфиденциальности](https://github.com/andrey-torlopov/ATPlayer/blob/main/PRIVACY.md) и [страница поддержки](https://github.com/andrey-torlopov/ATPlayer/blob/main/SUPPORT.md). Публичный контакт: [mail@torlopov.dev](mailto:mail@torlopov.dev).
- [Проверка ограничений текстовых полей](metadata/validation.json).
- [Оригинальные демо-аудиофайлы CC0](demo-audio/README.md), [проверка WAV](demo-audio/verification.json). Эти файлы предназначены для снимков интерфейса и App Review, не включены в приложение.
- [Демопакет App Review](review-attachment/ATPlayer-Review-Demo.zip), [инструкция и CC0](review-attachment/README.md), [проверка и статус загрузки](review-attachment/verification.json). Вложение подтверждено в ASC 1 ноября в 17:20 MSK.
- [Настройки локального экспорта](ExportOptions.plist) и отдельные [настройки выполненной загрузки](UploadOptions.plist).

## Выполненные этапы и доказательства

| Этап | Результат | Доказательство |
| --- | --- | --- |
| Release для iOS Simulator | BUILD SUCCEEDED; ошибок и предупреждений компилятора нет | [build-simulator.log](build-simulator.log) |
| Подписанный Release archive | ARCHIVE SUCCEEDED; app и extension подписаны Apple Distribution | [build-archive.log](build-archive.log), [ATPlayer.xcarchive](ATPlayer.xcarchive), [archive-verification.json](archive-verification.json) |
| Локальный App Store export | EXPORT SUCCEEDED; версия и build сохранены | [export-archive.log](export-archive.log), [ATPlayer.ipa](export/ATPlayer.ipa) |
| Проверка IPA | Подписи, profiles, metadata и privacy manifest проверены; export/packaging warnings отсутствуют | [ipa-verification.json](ipa-verification.json) |
| Загрузка в App Store Connect | Upload succeeded, xcodebuild exit 0; пакет принят на processing | [upload-archive.log](upload-archive.log), [upload-result.json](upload-result.json) |
| Обработка и выбор build | Apple завершила processing; 1.0.2 (1) прикреплён | Последующее наблюдение основного агента в App Store Connect |
| Локализации карточки | RU и EN тексты сохранены; EN subtitle `Local music. Just press play.` подтверждён после перезагрузки | Последующее наблюдение основного агента в App Store Connect |
| Скриншоты карточки | 4 iPhone и 2 iPad JPEG; RU iPad — 2 прямых изображения, EN iPad — Using Existing Assets; RU/EN iPhone — 4 Existing Assets из большого размера. Проверка обоих языков пройдена | Последующее наблюдение основного агента в App Store Connect |
| Цена и доступность | Бесплатно в 175 регионах; Mac и Apple Vision отключены | Последующее наблюдение основного агента в App Store Connect |
| Возрастной рейтинг | 4+ сохранён | Последующее наблюдение основного агента в App Store Connect |
| Content Rights | Ответ владельца `No` получен; значение сохранено и подтверждено после перезагрузки | Подтверждение владельца и последующее наблюдение основного агента |
| App Privacy | Опубликована; в UI отображалось `Published a few seconds ago by Andrey Torlopov` | Последующее наблюдение основного агента в App Store Connect |
| Header / Search Results | RU Header: 1 of 1; RU Search Results: Use Header включён, 1 of 1. EN использует Russian Header и Russian Search Results. RU Device Preview Product Page и Search Results — visual PASS | [creative-assets/verification.json](creative-assets/verification.json); наблюдение основного агента в ASC |
| App Review attachment | `ATPlayer-Review-Demo.zip` загружен, filename виден без Processing; соответствующий абзац Notes сохранён | Наблюдение основного агента в ASC, 1 ноября 17:20 MSK; [verification.json](review-attachment/verification.json) |
| App Review | Отправлено 1 ноября 2026 года в 17:28 MSK; Waiting for Review, Items Submitted (1), Draft Submissions 0 | Основной агент нажал Submit for Review и открыл submission details; [submission-result.json](submission-result.json) |
| Выпуск после одобрения | Automatic release after approval включён | Наблюдение основного агента в ASC |

Для скриншотов собран актуальный app: `/private/tmp/ATPlayer-AppStore-Simulator/Build/Products/Release-iphonesimulator/ATPlayer.app`. Старое `SRC/ATPlayer/build/Release-iphonesimulator/ATPlayer.app` не является артефактом этого релиза.

SHA-256 экспортированного IPA: `04cb9547d4681922e7527ba100fcc560059c5a30581d9044075ce30b939249d0`.

При upload использована существующая авторизация Xcode. Новые credentials/API keys не создавались, login/2FA и `-allowProvisioningUpdates` не потребовались. `manageAppVersionAndBuildNumber=false`: Apple-загрузка не меняла номер сборки. Внутренний ContentDelivery log после принятия пакета сообщил об отсутствующем локальном resume-файле; итог операции остался успешным, повторная загрузка не выполнялась. Деталь сохранена в `upload-result.json`.

## Проверенные параметры релиза

| Параметр | Результат |
| --- | --- |
| App Store Connect app ID | `6829444190`, подтверждён distribution logs |
| Bundle ID приложения | `dev.torlopov.atplayer.ios` |
| Bundle ID расширения | `dev.torlopov.atplayer.ios.extension` |
| Team | `79798GRSHW` |
| Версия / build | `1.0.2` / `1` у обоих targets |
| Платформы | iPhone и iPad, iOS/iPadOS 26.2+ |
| Интерфейс и development region | Русский, `ru`; main app объявляет только `ru` |
| Toolchain / SDK архива | Xcode 27.2, build 27B52; `iphoneos27.2` |
| Профили | `ATPlayer iOS App Store`, `ATPlayer iOS Extension App Store` |
| Срок профилей | До 1 ноября 2027 года; bundle IDs и team совпадают |
| Подпись | `codesign --verify --deep --strict` успешно для app и extension в archive и IPA |
| Entitlements | `get-task-allow=false`, App Store profiles без списка устройств |
| Иконки | Три варианта 1024 × 1024, без alpha |
| Privacy manifest | Включён в финальный app; совпадает с исходником |
| Сбор данных в manifest | Tracking выключен, collected data types пусты |
| Encryption declaration | `ITSAppUsesNonExemptEncryption=false` |

## Изменения проекта, вошедшие в релиз

- `SRC/ATPlayer/ATPlayer/PrivacyInfo.xcprivacy`: own UserDefaults — `CA92.1`; SystemBootTime для интервалов — `35F9.1`; tracking выключен, collected data types пусты.
- `SRC/ATPlayer/ATPlayer/Info.plist`: русский язык и `ITSAppUsesNonExemptEncryption=false` по аудиту используемых API.
- `SRC/ATPlayer/ATPlayer.xcodeproj/project.pbxproj`: development region `ru`; `MARKETING_VERSION=1.0.2` для обоих targets во всех configurations, `CURRENT_PROJECT_VERSION=1`.
- `SRC/ATPlayer/ATPlayer/Views/Components/V1/SettingsViewV1.swift`: доступные ссылки на опубликованную privacy policy и email поддержки в разделе «О приложении».

Контрольные суммы этих исходников на момент архивации записаны в [archive-verification.json](archive-verification.json). Код воспроизведения в этом этапе не менялся. Этот отчёт не утверждает, что текущий Git tag или HEAD тождественен содержимому архива.

## Следующий этап

Ожидать результата App Review. При запросе Apple ответить через App Store Connect; после одобрения выпуск настроен автоматически. Публичную ссылку и badge добавлять только после проверки доступности приложения в App Store.

Идентификатор submission: `1170ab45-3ddf-4da3-8883-731f7642b862`. [Внутренняя страница submission](https://appstoreconnect.apple.com/apps/6829444190/distribution/reviewsubmissions/details/1170ab45-3ddf-4da3-8883-731f7642b862). На ней подтверждены iOS Submission, Waiting for Review, Items Submitted (1), App Version 1.0.2 (1), Date Submitted Nov 1, 2026 at 5:28 PM.

Личный телефон и другие непубличные review contacts в отчёт не включены. Страницы поддержки и privacy опубликованы; Content Rights = No и опубликованная App Privacy подтверждены после сохранения. Header/Search assets и демопакет загружены.

## Откат и границы проверки

Публичного релиза ATPlayer в этой карточке ещё нет; last known good опубликованной версии отсутствует. До submission карточка редактируется. После submission запрос можно снять с проверки. После публикации бинарник заменяется новой версией; быстрое возвращение старого бинарника не гарантировано. Удаление из продажи не откатывает установки пользователей. Миграции данных в подготовленных изменениях нет.

Выполнены `plutil -lint`, проверка diff, проверки текстовых полей и WAV, Release build/archive/export, подписи и profiles финального IPA, проверка privacy manifest и успешная передача пакета Apple. Processing и подготовка карточки подтверждены отдельно в UI App Store Connect. Финальная отправка на App Review выполнена и подтверждена на странице submission. Одобрение Apple и публичная доступность ещё не подтверждены.

## Источники Apple

- [Создание карточки](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/).
- [Требования к скриншотам](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).
- [Загрузка скриншотов](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/).
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
- [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/).
- [Required-reason API categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
- [Encryption key](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption).
