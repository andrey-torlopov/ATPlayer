# ATPlayer artwork

The English and Russian READMEs use two original vector compositions:

- `banner-en.svg` and `banner-ru.svg`: the product name, listening message, radial audio motif, and a short illustrative playlist.
- `listen-en.svg` and `listen-ru.svg`: files → playlist → listening.

The compositions use ATPlayer's calm green palette. They contain no third-party artwork, commercial album covers, embedded font files, or external resources. They are conceptual illustrations, not screenshots of the app. The track names are fictional demo labels.

Regenerate all four files from the repository root:

```sh
python3 docs/tools/generate_artwork.py
python3 docs/tools/validate_docs.py
```

Only Python's standard library is required. SVG is the source format and renders directly on GitHub. App Store screenshots are a separate set of real app captures; do not use these illustrations as substitutes.

## Русский

Баннеры и схема «файлы → плейлист → прослушивание» нарисованы специально для ATPlayer. В них нет чужих иллюстраций, коммерческих обложек, встроенных файлов шрифтов и внешних ресурсов. Это иллюстрации идеи приложения, а не его скриншоты. Названия треков вымышлены.

Команды выше воспроизводят SVG и проверяют документацию. Для App Store используются отдельные реальные снимки приложения.
