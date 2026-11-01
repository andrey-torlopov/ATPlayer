# ATPlayer 1.1.0 (2) — App Review

1 ноября 2026 года, Europe/Moscow.

**Версия 1.1.0 (2) отправлена на App Review в 22:28 MSK. Подтверждены Waiting for Review, Items Submitted (1), Draft Submissions (0). Включён автоматический выпуск после одобрения Apple. Публичный выпуск ещё не состоялся.**

[Заявка в App Store Connect](https://appstoreconnect.apple.com/apps/6829444190/distribution/reviewsubmissions/details/9cc2260c-8b1f-413b-a9c0-7d3e15bdc5a8). Идентификатор: `9cc2260c-8b1f-413b-a9c0-7d3e15bdc5a8`.

Предыдущая заявка `1170ab45-3ddf-4da3-8883-731f7642b862` для **1.0.2 (1)** отозвана по запросу владельца. После отмены наблюдался статус **Developer Rejected**. Старый бинарник не удалялся из App Store Connect; из карточки убрана его привязка и выбрана новая сборка.

## Что отправлено

- Текущий код после коммитов `e09052b` (архитектура), `bc37384` (папки и кеш), `bb47bb9` (фильтрация и порядок плейлистов). Исходный HEAD при подготовке — `f77817306278ef9621053441b1326f6ddaecd1b4`; этот коммит с названием Release 1.1.0 сам по себе менял только Xcode user state.
- Номера обоих targets приведены к **1.1.0 / 2**. В сборку вошло дополнение privacy manifest: FileTimestamp / `3B52.1`, поскольку приложение читает даты изменения выбранных пользователем файлов для актуальности кеша.
- Bundle ID: `dev.torlopov.atplayer.ios`; extension: `dev.torlopov.atplayer.ios.extension`; team: `79798GRSHW`. iPhone/iPad, iOS 26.2+.
- `.xcodeproj` и локальный SwiftPM сохранены. Функциональный код на этапе релиза не менялся.

## Проверка артефакта

| Проверка | Результат |
| --- | --- |
| Release archive | ARCHIVE SUCCEEDED, ошибок/предупреждений компилятора не обнаружено |
| App Store export | EXPORT SUCCEEDED |
| Подписи app и extension | `codesign --verify --deep --strict` — PASS у архива и экспортированного IPA |
| Provisioning | App Store distribution, правильные bundle IDs/team, `get-task-allow=false`, без списка устройств |
| Версии bundles | 1.1.0 (2), app и extension |
| Privacy manifest | Совпадает с исходником; tracking false, collected data types пусты; FileTimestamp 3B52.1, UserDefaults CA92.1, SystemBootTime 35F9.1 |
| Проверки функционального кода | 53 / 53 XCTest и UI drag/relaunch — [предыдущая проверка того же кода](../PlaybackModes-2026-11-01/folder-filter-and-playlist-order-verification.md) |
| Upload | Succeeded, 22:20:39 MSK; затем Apple завершила processing, build 2 стал доступен и выбран |
| Финальная заявка | Waiting for Review, ровно один item 1.1.0 (2), черновиков нет |

Проверка подписи внутри ограниченного sandbox первоначально вернула `CSSMERR_TP_NOT_TRUSTED`; повторная проверка с доступом к системному trust service прошла. Изменения сертификатов или доверия не выполнялись.

SHA-256 экспортированного IPA: `4a9f3d4d0074e7959bd2d37ad681ed0811d7b60a0c94ff4866a7d9a96766ae57`.

Доказательства: [archive-verification.json](archive-verification.json), [ipa-verification.json](ipa-verification.json), [upload-result.json](upload-result.json), [submission-result.json](submission-result.json). Архив, IPA и полные build/upload logs остаются локальными и исключены из Git. Использована существующая авторизация Xcode, без новых API-ключей и изменения provisioning-настроек.

## Карточка приложения

Сохранены RU/EN **Description, Promotional Text, Keywords, Subtitle** и новые App Review Notes:

- [Русский текст](metadata/ru-RU.md), [English text](metadata/en-US.md).
- [Review Notes](metadata/review-notes.md): плейлисты, папки, перестановка, режимы воспроизведения, временный кеш и демо.
- [Проверка лимитов](metadata/validation.json); повторяется командой `python3 Artifacts/AppStore-1.1.0-2026-11-01/metadata/validator.py`.
- What's New подготовлен локально, но поле не показывалось для первого публичного выпуска; не заявляем его публикацию.

В описания добавлены отсутствие рекламы, трекинга, аналитики использования и отправки данных разработчику, офлайн-воспроизведение локальной музыки, плейлисты и открытие папок. Абсолютное «не использует сеть» заменено точной формулировкой: доступ к выбранным iCloud/сетевым источникам может требовать сети. Собственного серверного клиента или аналитических SDK в production sources не найдено.

В App Privacy проверено **Published / Data Not Collected**. URL ведёт на [PRIVACY.md](../../PRIVACY.md), обновлённую для 1.1.0. Демо-вложение `ATPlayer-Review-Demo.zip` сохранено, приватные review contacts оставлены без изменений и не включены в отчёт. Исходные скриншоты и header assets не заменялись. Браузер не показывал отдельного поля What's New и не потребовал нового соглашения или авторизации.

## Release gate и откат

- Operation: загрузка нового бинарника, отзыв старой заявки, обновление метаданных, отправка 1.1.0 с automatic release.
- Environment: App Store Connect, app 6829444190.
- Confirmation: прямой запрос владельца в текущем чате на отзыв, публикацию и правку описания. No silent deploy.
- Last known artifact: прежняя подписанная 1.0.2 (1) сохранена; опубликованной last known good версии ещё нет.
- До одобрения: открыть новую заявку → Cancel Submission; затем отредактировать версию и выбрать нужный сохранённый build, повторно проверить данные перед отправкой. Отмена не сохраняет место в очереди. Срок обработки отмены и повторного ревью задаёт Apple, точное время восстановления не гарантировано.
- После публикации: мгновенный возврат старого бинарника не гарантируется; требуется корректирующий выпуск через App Review. Снятие с продажи не откатывает установленные копии.
- На этапе релиза миграции данных не вводились. Рефакторинг сохраняет прежнюю SwiftData-схему плейлистов, папки имеют отдельный файл корней; совместимость старой схемы покрыта тестом.
- После любого отката: проверить selected version/build, release mode, локализации и фактический статус заявки в App Store Connect.

Реальные iCloud/SMB, физическое устройство и публичная загрузка из App Store на этом этапе не проверялись. Ожидание решения Apple — внешний этап; отправка не означает одобрение.

## Источники

- [Apple: remove a submission from review](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/remove-a-submission-from-review).
- [Apple: required reason APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
- [Apple: App Privacy details](https://developer.apple.com/app-store/app-privacy-details/).

TRACE:
- Skill: deploy-ops.
- Task folder: none.
- References read: deploy-gates; предыдущие материалы App Store; исходники, manifests, build settings; Apple Help; текущая Safari UI.
- Knowledge read: devops rules, ci-pipelines, verification.
- Patterns/policies applied: preflight, явная авторизация, проверка происхождения и подписей артефакта, rollback, минимизация приватных данных.
- Verification: archive/export/signatures/profiles/manifest; UI save/build/submit; metadata validator; git diff check.
- Residual risk: App Review и реальная работа внешних провайдеров/устройств; публичная доступность пока отсутствует.
