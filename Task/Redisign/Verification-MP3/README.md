# Исправление запуска MP3 и положения ошибки

17 октября 2026. Исходники: `SRC/ATPlayer/ATPlayer/Services/AudioPlaybackService.swift` и `Views/Components/V1/ATPlayerRootViewV1.swift` относительно папки приложения.

## Диагноз

Перед запуском аудиодвижка код задавал категорию `.playback` с явными опциями `.allowAirPlay` и `.allowBluetoothA2DP`. Согласно [Apple: allowAirPlay](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowairplay), явно задавать `allowAirPlay` разрешено только с `.playAndRecord`. Для `.playback` система поддерживает AirPlay и A2DP автоматически; см. [Apple: allowBluetoothA2DP](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowbluetootha2dp).

Несовместимая явная опция — подтверждённый дефект контракта API и наиболее вероятная причина описанного отказа на устройстве. Точный NSError исходного отказа не сохранился: прежний общий catch заменял ошибки настройки категории, активации сессии и запуска engine одной ошибкой `audioUnavailable`. После изменения повторный запуск на физическом iPhone не выполнялся.

## Изменения

- Для `.playback` используется `mode: .default, options: []`.
- В журнал `torlopov.atplayer` / `AudioPlayback` при ошибке записываются `stage`, системные `domain` и `code`. Этапы: `configureSession`, `activateSession`, `startEngine`. `userInfo`, пути, имена и содержимое аудиофайлов в эту запись не включаются.
- Баннер находится перед компонентом плейлистов: под плеером в портрете и над плейлистами справа в двух колонках. Общий компонент используется обеими компоновками.
- V0, модель данных, подписи и настройки проекта не менялись.

## Проверка

Debug-сборка основного приложения и расширения для Simulator прошла без предупреждений: [build.log](build.log).

Временный UIKit harness скомпилирован с настоящими production-сервисами, моделью, VM и компонентами V1, с флагами actor isolation/concurrency проекта. Запущен на отдельном QA iPhone 17 Pro, iOS 26.5 Simulator. Собственные MP3 созданы локально из синусоидального сигнала через ffmpeg/libmp3lame; файлы включены в эту папку.

Подсчёт Python по [regression-results.json](regression-results.json):

```text
MP3: successful / all = 20 / 20
All: successful / all = 109 / 109
```

Для mono 44,1 кГц и stereo 48 кГц проверены запуск, длительность, категория/режим сессии, таймер, реальный спектр, перемотка на паузе, продолжение и EOF. Через настоящую VM проверены импорт обоих MP3 и воспроизведение импортированного файла. Повторно выполнены прежние проверки аудио, SwiftData, bookmarks, удаления, переходов, экспорта и отмены.

Лог: [runtime.log](runtime.log). Исходники: [RegressionHarness.swift](RegressionHarness.swift), [LogicRegression.swift](LogicRegression.swift). [SHA-256](source-sha256.json) проверенных production-файлов сопоставлены с текущими исходниками. Предупреждения в [compile.log](compile.log) относятся к старому UIKit bootstrap временного harness; сборка production-приложения предупреждений не содержит.

Положение ошибки проверено через реальный `ATPlayerRootViewV1` в отдельном UI-образце с заданным текстом ошибки. Это проверка отображения, а не воспроизведение аппаратного отказа: [портрет](error-portrait.png), [две колонки](error-landscape.png). Тестовое приложение и QA Simulator после проверки остановлены.

## Ограничения

MP3 пользователя не предоставлен; проверялись валидные синтетические MP3. Исходный аппаратный отказ и исправленная сборка на физическом iPhone не проверены. Системные ошибки других этапов запуска, реальные AirPlay/Bluetooth и занятый аудиовыход требуют проверки на устройстве. Диагностическая запись позволяет различить эти случаи при следующем отказе.
