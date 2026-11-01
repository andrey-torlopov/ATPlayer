# Фильтрация папок и перестановка плейлистов

Проверено 2026-11-01. Дополнение к `folders-verification.md` по последующим запросам пользователя. Перестановка плейлистов теперь входит в реализованный объём. Изменения ещё не опубликованы.

## Поведение

- В браузере скрываются подпапки, во всём видимом дереве которых нет поддерживаемого аудио. Родители вложенных альбомов остаются. Проверка учитывает тот же набор расширений, что и воспроизведение: MP3, M4A, AAC, WAV, AIFF, FLAC, ALAC, CAF; регистр расширения не важен.
- Выбранный новый корень без музыки не сохраняется и не меняет текущую навигацию. Уже сохранённые корни автоматически не удаляются.
- Обход проверяет метаданные, прекращается при первом аудиофайле, исключает скрытые файлы, пакеты и символические ссылки. Результаты дерева не сохраняются. Отдельная последовательная очередь сканирования не блокирует очередь подготовки выбранного файла.
- При недоступности потомка его содержимое считается неизвестным: папка остаётся видимой, доступные соседние файлы сохраняются в списке. Отмена и общий timeout не подавляются.
- На экране по-прежнему только непосредственные папки и файлы; в воспроизведение и prefetch входят только аудиофайлы открытого уровня. Вложенные треки ради фильтрации не скачиваются.
- Кнопка со стрелками вверх/вниз возле «Плейлисты» открывает «Порядок плейлистов». Стандартные ручки `List.onMove` меняют порядок с немедленным сохранением. Кнопка недоступна при импорте или если плейлистов меньше двух.
- Сохранение порядка проверяет полный набор UUID и выполняется одной операцией с rollback при ошибке. Текущий трек, позиция, пауза и история shuffle сохраняются; обычные Next/Previous учитывают новый порядок.

## Проверки

Пакет: `SRC/ATPlayer/LocalPackages/ATPlayerKit`.

```sh
xcodebuild -scheme ATPlayerKit-Package \
  -destination 'platform=iOS Simulator,id=A0EA97FA-8776-4762-96D7-CEA800200E5A' \
  -derivedDataPath /tmp/ATPlayerPackageDerived \
  -resultBundlePath /tmp/ATPlayerFolderVisibilityOrderTests.xcresult \
  CODE_SIGNING_ALLOWED=NO test
```

**TEST SUCCEEDED. Пройдено / всего = 53 / 53; ошибок 0.** Число получено Python-скриптом по завершённым `Test Case` из `/tmp/atplayer-folder-visibility-order-tests.log`.

Новые проверки покрывают пустые и немузыкальные деревья, вложенный FLAC, все поддерживаемые расширения, скрытые файлы, циклические ссылки, отсутствие аудиокопирования при сканировании, обновление после добавления/удаления музыки, недоступную подпапку, отказ от пустого корня, повторное использование списка при импорте и поздний импорт после навигации. Проверки порядка покрывают одинаковые имена, неверный набор UUID, повторное открытие базы, ошибку сохранения, обычные переходы и shuffle без сброса позиции.

Из корня репозитория:

```sh
xcodebuild -project SRC/ATPlayer/ATPlayer.xcodeproj -scheme ATPlayer \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/ATPlayerArchitectureDerived \
  CODE_SIGNING_ALLOWED=NO build
```

**BUILD SUCCEEDED**, без compiler warnings/errors. Лог: `/tmp/atplayer-folder-visibility-order-build.log`. В package-test build были только сообщения AppIntents metadata extraction skipped для тестовых целей.

`git diff --check` прошёл. Независимый повторный code review не выявил оставшихся конкретных замечаний.

## Интерфейс

На `ATPlayer Redesign QA`, iOS 26.5, через интерфейс создан плейлист `QA Reorder`. В редакторе он перетащен за правую ручку выше `My Music`. После принудительного перезапуска приложения порядок `QA Reorder → My Music` подтверждён и на главном экране, и в редакторе. Тестовый плейлист оставлен в QA-симуляторе.

![Порядок после перезапуска](playlist-order.png)

## Ограничения

Реальные iCloud/SMB-провайдеры и физическое устройство в этой доработке не проверялись. Проверка большого дерева без музыки требует чтения метаданных всех доступных потомков и может завершиться timeout; состояние ошибки не сохраняется как «папка пуста». Полный UI-сценарий фильтрации через внешний провайдер не выполнялся; фильтрация проверена XCTest на настоящих локальных файловых деревьях.

TRACE:
- Skill: implementation-from-plan.
- Task folder: none.
- References read: delivery-pipeline.md; исходники folder service/browser, playlist editor/model/storage и тесты; пользовательская документация.
- Knowledge read: Swift rules, verification, common/platform/performance summaries, naive-directory-traversal, async-test-pitfalls; iOS rules.
- Patterns/policies applied: module boundaries, prefetched URL resource values, bounded worker queues, generation guards, UUID identity, transactional persistence; сохранены посторонние изменения Xcode user state.
- Verification: 53 / 53 XCTest; app/widget build; UI drag/relaunch; diff check; independent review.
- Residual risk: реальные внешние провайдеры и физическое устройство не проверены.
