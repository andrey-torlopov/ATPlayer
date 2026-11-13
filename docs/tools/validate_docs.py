#!/usr/bin/env python3
"""Check ATPlayer's public documentation links and standalone SVG safety."""
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
FILES = [ROOT / 'README.md', ROOT / 'README-ru.md', *sorted((ROOT / 'docs').rglob('*.md'))]
link_count = 0


def exact_case_path_exists(path):
    """Enforce GitHub's case-sensitive paths even on a case-insensitive Mac."""
    current = ROOT
    for part in path.relative_to(ROOT).parts:
        entries = {entry.name: entry for entry in current.iterdir()}
        if part not in entries:
            return False
        current = entries[part]
    return current.exists()


for path in FILES:
    text = path.read_text(encoding='utf-8')
    if re.search(r'/(?:Users|Volumes|private/tmp)/', text):
        raise SystemExit(f'Private machine path in {path.relative_to(ROOT)}')
    if '\ufffd' in text:
        raise SystemExit(f'Invalid Unicode in {path.relative_to(ROOT)}')
    links = re.findall(r'!?\[[^\]]*\]\(([^)]+)\)', text)
    links += re.findall(r'(?:src|href)="([^"]+)"', text)
    for target in links:
        parts = urlsplit(target.strip('<>'))
        if parts.scheme or parts.netloc or not parts.path:
            continue
        destination = (path.parent / unquote(parts.path)).resolve()
        if not destination.is_relative_to(ROOT) or not exact_case_path_exists(destination):
            raise SystemExit(f'Broken local link in {path.relative_to(ROOT)}: {target}')
        link_count += 1

for language in ('en', 'ru'):
    folder = ROOT / 'docs' / language
    peer = ROOT / 'docs' / ('ru' if language == 'en' else 'en')
    for path in folder.glob('*.md'):
        if not (peer / path.name).is_file():
            raise SystemExit(f'Missing paired translation for {path.relative_to(ROOT)}')

artwork = sorted((ROOT / 'docs' / 'assets').glob('*.svg'))
for path in artwork:
    tree = ET.fromstring(path.read_text(encoding='utf-8'))
    if not tree.attrib.get('viewBox') or not tree.attrib.get('aria-labelledby'):
        raise SystemExit(f'Missing dimensions or accessibility title: {path.name}')
    for element in tree.iter():
        tag = element.tag.rsplit('}', 1)[-1]
        if tag in ('script', 'foreignObject', 'image'):
            raise SystemExit(f'Unexpected SVG dependency: {path.name}: {tag}')
        if any(key.rsplit('}', 1)[-1] == 'href' and not value.startswith('#')
               for key, value in element.attrib.items()):
            raise SystemExit(f'External SVG link: {path.name}')

print(f'Checked {len(FILES)} Markdown files and {link_count} local links: all resolve with exact case.')
print(f'Checked {len(artwork)} standalone SVGs: XML, dimensions, accessible titles, no external artwork.')
print('English/Russian documentation pairs match; no private machine paths found.')
