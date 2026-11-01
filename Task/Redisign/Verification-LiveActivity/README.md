# ActivityKit: соответствия протоколам вне MainActor

17 октября 2026.

В проекте установлено `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Исходные объявления общей модели Live Activity не задавали изоляцию явно. Все четыре сообщения в `ATPlayerActivityService` относятся к одному соответствию `ATPlayerActivityAttributes: ActivityAttributes`; вложенный ContentState также получал изолированные соответствия Codable/Hashable.

В `SRC/ATPlayer/ATPlayer/LiveActivity/ATPlayerActivityAttributes.swift` внешний тип объявлен `nonisolated` и `Sendable`, а ContentState — `Sendable`. Это неизменяемые значения String, TimeInterval, Bool и Date. Имена и типы свойств и формат Codable сохранены. Сервис продолжает работать на MainActor. Изменений project settings и включения Live Activities нет.

Проверка:

- Обычная локальная проверка сервиса с iOS 26.5 SDK не воспроизвела исходные предупреждения. Поэтому добавлена отдельная compile-only проверка реальной модели и сервиса из явного `@concurrent` контекста: [ConcurrentActivityProbe.swift](ConcurrentActivityProbe.swift). Она проверяет ActivityAttributes/Sendable/SendableMetatype, JSON encode/decode, Hashable, ActivityContent, update и end.
- С исходными объявлениями эта проверка завершается ошибками изоляции: [before.log](before.log), [OriginalAttributes.swift](OriginalAttributes.swift). С исправленной моделью при Swift 6, complete concurrency и warnings-as-errors — exit 0, пустой [after.log](after.log). Точные команды: [commands.json](commands.json).
- Debug-сборка `ATPlayer`, включая widget extension, для generic iOS Simulator проходит без compiler warnings/errors: [build.log](build.log). Использовано ранее данное разрешение пользователя на сборку. [SHA-256](source-sha256.json) фиксируют проверенные production-исходники.

Это проверка компиляции. Compile-only probe не выполняет операции ActivityKit на устройстве. Визуальная проверка Live Activity и его реальный жизненный цикл в этот прогон не входят. Предыдущие аудиопроверки не повторялись, поскольку runtime-логика не изменена; их результаты и хеши относятся к предыдущему этапу.

Справка по изоляции по умолчанию и `@concurrent`: [Swift 6.2 Released](https://www.swift.org/blog/swift-6.2-released/#approachable-concurrency).
