# Аудиосессия: предупреждения главного потока

17 октября 2026. Этот прогон проверяет исходники после исправления предупреждений `SessionCore.mm` / `AVAudioSession_iOS.mm`; предыдущий прогон MP3 сохранён отдельно.

## Причина и изменение

`AudioPlaybackService` изолирован `MainActor`. Синхронные `setCategory` и `setActive` выполнялись непосредственно в его методе запуска, включая повторные вызовы при продолжении и перемотке. Это соответствует сообщению системы о возможной блокировке UI.

В установленном SDK `iPhoneSimulator26.5.sdk`, `AVFAudio.framework/Headers/AVAudioSession.h`, активация `setActive` объявлена синхронной. Существующий `activateWithOptions:completionHandler:` в этом SDK недоступен для iOS. Исправление совместимо с текущим SDK:

- `PlaybackAudioSession` выполняет настройку и активацию на отдельной последовательной очереди `torlopov.atplayer.audio-session`; результат передаётся через checked continuation. Вызовы не зависят от исполнителя вызывающего Swift Task.
- Категория, режим и options проверяются на этой же очереди. Если настройки совпадают, повторного `setCategory` нет.
- UI и граф `AVAudioEngine` остаются на `MainActor`. Они продолжают запуск только после активации и проверки поколения запроса и отмены Task.
- `isStarting` отражает ожидание активации. Pause, stop, seek, interruption и смена файла отменяют ожидающий запуск. Поздний результат или ошибка предыдущего запроса не останавливает новый трек и не появляется в UI.
- VM владеет security-scoped grant до точки `await` и проверяет актуальность запроса после неё. Кнопка V1 показывает паузу и во время ожидающего запуска.

Изменены production-файлы: `Services/AudioPlaybackService.swift`, `ViewModels/ATPlayerViewModel.swift`, `Views/Components/V1/PlayerPanelV1.swift` относительно `SRC/ATPlayer/ATPlayer/`.

## Проверка

Debug-сборка `ATPlayer` вместе с widget extension для `generic/platform=iOS Simulator` прошла: [build.log](build.log). Разрешение на сборку и Simulator получено от пользователя ранее в этом чате. Signing и capabilities не менялись.

В отдельном приложении harness с фактическими production-исходниками выполнены проверки на iPhone 17 Pro / iOS 26.5 Simulator. Подсчёт Python по [regression-results.json](regression-results.json):

```text
All: successful / all = 127 / 127
Session: successful / all = 18 / 18
MP3: successful / all = 20 / 20
build.log: relevant warnings = 0
compile.log: relevant warnings = 0
runtime.log: relevant warnings = 0
```

Новые проверки удерживают реальный вызов активации тестовым семафором и управляют плеером с MainActor. Проверены stop и pause во время активации, продолжение, повторное play, серия seek, замена трека, запоздалая ошибка старого трека, отмена внешнего Task, выбор и ошибки VM, отмена кнопкой паузы. Приём подтверждённого вызова и состояние плеера задают порядок теста; polling ограничен таймаутом.

Только тестовый executable временно перехватывает Objective-C методы `setCategory:mode:options:error:` и `setActive:withOptions:error:`. Перехват вызывает исходные методы Apple, кроме двух намеренно смоделированных отказов старого запроса. Записаны `categoryCalls=1`, `activationCalls=12`, `mainThreadCalls=0`. Следовательно, подтверждено исполнение обоих системных методов вне главного потока и отсутствие лишней настройки категории. Сообщения `UI unresponsiveness`, `SessionCore.mm`, `AVAudioSession_iOS.mm` в итоговом runtime-логе отсутствуют. Системные информационные сообщения при создании тестовых PCM-файлов не относятся к проверяемым предупреждениям.

Исходники тестов: [RegressionHarness.swift](RegressionHarness.swift), [SessionRegression.swift](SessionRegression.swift), [LogicRegression.swift](LogicRegression.swift). Команда компиляции: [compile-command.json](compile-command.json), plist harness: [Harness-Info.plist](Harness-Info.plist), результат компиляции: [compile.log](compile.log), runtime: [runtime.log](runtime.log). Два синтетических MP3 включены в эту папку. Проверенные production- и test-исходники зафиксированы в [source-sha256.json](source-sha256.json).

Первый прогон нового перехвата использовал неверную перегрузку `setActive:error:`. Из-за этого gate не получил вызова, две проверки завершились FAIL, а защита от повторной установки gate остановила harness. Лог сохранён как [runtime-probe-setup-failure.log](runtime-probe-setup-failure.log). После исправления selector выполнен полный успешный прогон выше; production-код между этими прогонами не менялся.

## Ограничения

Проверка на физическом устройстве, реальные звонки, AirPlay и Bluetooth не выполнялись. Указанные диагностические сообщения предоставлены пользователем с устройства; отсутствие их на устройстве после исправления ещё не подтверждено. Синхронный системный вызов, уже выполняющийся на рабочей очереди, невозможно прервать: отмена запрещает последующее воспроизведение и публикацию устаревшей ошибки. Деактивация аудиосессии и перенос всего аудиографа на другую очередь в это изменение не входят.

QA Simulator и тестовое приложение после проверки остановлены. Предыдущие результаты и SHA-256 в `Verification-MP3/` и `Verification/` относятся к своим историческим версиям.
