# Проверка редизайна ATPlayer

17 октября 2026, iOS 26.5 Simulator. Основной отчёт: [implementation-report.md](../implementation-report.md).

Это результаты первого этапа. Актуальная проверка после исправления MP3 и аудиосессии: [Verification-MP3](../Verification-MP3/README.md).

- `build.log`: итоговая Debug-сборка приложения и расширения, без предупреждений.
- `regression-results.json`: результаты реального Swift harness; успешные / все = 89 / 89.
- `runtime-final.log`: итоговый вывод harness; `runtime-initial.log` сохраняет первый прогон с ошибочно строгим ожиданием мгновенного нуля спектра.
- `RegressionHarness.swift`, `LogicRegression.swift`: исполненные проверки actual production sources во временном UIKit-приложении. Они не включаются в production target.
- `source-sha256.json`: отпечатки production-файлов на момент первого этапа, до исправления аудиосессии.
- PNG: реальные скриншоты основного приложения, снятые через Simulator. Музыка и названия в плейлисте — локальные синтетические тестовые файлы.

Итоговые проверки выполнялись настоящими Swift-сервисами. Аппаратные сценарии и непроверенные провайдеры перечислены в основном отчёте.
