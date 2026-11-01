#!/usr/bin/env python3
"""Regenerate original ATPlayer SVG artwork; uses only Python's standard library."""
from pathlib import Path
from math import cos, sin, pi
from html import escape

OUT = Path(__file__).resolve().parents[1] / 'assets'
OUT.mkdir(parents=True, exist_ok=True)


def waveform(x, y, color='#a9ccba'):
    heights = [11, 24, 37, 22, 14]
    return '<g stroke="'+color+'" stroke-width="5" stroke-linecap="round">'+''.join(
        f'<path d="M{x+i*10} {y-h/2}v{h}"/>' for i,h in enumerate(heights))+'</g>'


def banner(lang):
    ru = lang == 'ru'
    subtitle = 'Включил и слушай.' if ru else 'Press play. Just listen.'
    eyebrow = 'ЛОКАЛЬНАЯ МУЗЫКА' if ru else 'LOCAL AUDIO PLAYER'
    footer = 'ВАШИ ФАЙЛЫ  /  ВАШ ПЛЕЙЛИСТ' if ru else 'YOUR FILES  /  YOUR PLAYLIST'
    playlist = 'МОЯ МУЗЫКА' if ru else 'MY MUSIC'
    tracks = ['Утренний свет', 'Тихий берег', 'Дорога домой'] if ru else ['Morning Light', 'Quiet Shore', 'The Way Home']
    rays=[]
    for i in range(64):
        angle=2*pi*i/64-pi/2
        length=11+21*(sin(i*0.72)**2)+9*(cos(i*0.27)**2)
        r=137
        x1,y1=1245+cos(angle)*r,233+sin(angle)*r
        x2,y2=1245+cos(angle)*(r+length),233+sin(angle)*(r+length)
        rays.append(f'<path d="M{x1:.2f} {y1:.2f}L{x2:.2f} {y2:.2f}"/>')
    rows=[]
    for i,track in enumerate(tracks):
        y=194+i*61
        if i==0:
            rows.append(f'<rect x="1476" y="{y-28}" width="338" height="55" rx="12" fill="#284338"/>')
        rows.append(f'<text x="1494" y="{y+7}" fill="'+('#b6e0c6' if i==0 else '#6d877a')+f'" font-size="18">0{i+1}</text>')
        rows.append(f'<text x="1540" y="{y+7}" fill="'+('#ecf5ef' if i==0 else '#a8b9b0')+f'" font-size="22">{escape(track)}</text>')
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="480" viewBox="0 0 1920 480" role="img" aria-labelledby="title desc">
<title id="title">ATPlayer — {subtitle}</title>
<desc id="desc">Original conceptual artwork: a circular audio player and a short playlist, beside the ATPlayer name. This is an illustration, not an app screenshot.</desc>
<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#0b1411"/><stop offset="1" stop-color="#1b2d24"/></linearGradient>
  <radialGradient id="glow"><stop stop-color="#537f66" stop-opacity=".23"/><stop offset="1" stop-color="#537f66" stop-opacity="0"/></radialGradient>
  <linearGradient id="dial" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#243b2f"/><stop offset="1" stop-color="#132019"/></linearGradient>
</defs>
<rect x="1" y="1" width="1918" height="478" rx="28" fill="url(#bg)" stroke="#31453a" stroke-width="2"/>
<g stroke="#b6dcc4" opacity=".045"><path d="M1020 0v480M1210 0v480M1400 0v480M1590 0v480M1780 0v480M990 96h930M990 192h930M990 288h930M990 384h930"/></g>
<ellipse cx="1340" cy="238" rx="470" ry="248" fill="url(#glow)"/>
<g font-family="Arial, Helvetica, sans-serif">
  <rect x="96" y="61" width="68" height="68" rx="21" fill="#1a3025" stroke="#456551" stroke-width="2"/>
  {waveform(110,95)}
  <text x="191" y="104" fill="#9eb8a9" font-size="22" font-weight="700" letter-spacing="4">{eyebrow}</text>
  <text x="89" y="265" font-size="130" font-weight="700" letter-spacing="-7" fill="#edf4ef">AT<tspan fill="#a9ccba">Player</tspan></text>
  <path d="M100 297h72" stroke="#a9ccba" stroke-width="4" stroke-linecap="round"/><path d="M190 297h25" stroke="#4d6b59" stroke-width="4" stroke-linecap="round"/>
  <text x="96" y="358" font-size="39" fill="#cfddd4">{subtitle}</text>
  <text x="98" y="424" font-size="21" font-weight="700" letter-spacing="3" fill="#7e9c89">{footer}</text>
  <path d="M965 58v364" stroke="#405b4a" opacity=".35"/>
  <g fill="none" stroke="#8ebaa0" stroke-width="4" stroke-linecap="round" opacity=".68">{''.join(rays)}</g>
  <circle cx="1245" cy="233" r="116" fill="url(#dial)" stroke="#3c5948" stroke-width="2"/>
  <circle cx="1245" cy="233" r="97" fill="none" stroke="#314c3c" stroke-width="4"/>
  <circle cx="1245" cy="233" r="97" fill="none" stroke="#b4d8bf" stroke-width="4" stroke-dasharray="405 610" transform="rotate(-90 1245 233)"/>
  <path d="M1222 199L1282 233L1222 267Z" fill="#b7d8c2" stroke-linejoin="round"/>
  <circle cx="1245" cy="412" r="23" fill="#2a4435" stroke="#52715c"/>
  <path d="M1238 400v24M1252 400v24" stroke="#c5dfcd" stroke-width="6" stroke-linecap="round"/>
  <path d="M1175 403v18M1194 403L1180 412L1194 421Z M1315 403L1329 412L1315 421Z M1334 403v18" fill="#9fb9a9" stroke="#9fb9a9" stroke-width="2"/>
  <rect x="1456" y="102" width="380" height="267" rx="26" fill="#15251d" stroke="#435d4c" stroke-width="2"/>
  <text x="1485" y="145" fill="#8daf9b" font-size="17" letter-spacing="3" font-weight="700">{playlist}</text>
  <path d="M1786 133h16M1794 125v16" stroke="#98b5a2" stroke-width="2" stroke-linecap="round"/>
  {''.join(rows)}
  <path d="M1456 399h380" stroke="#415d4b" opacity=".55"/>
  <text x="1479" y="433" fill="#8ba594" font-size="19" letter-spacing="2">iPhone  /  iPad</text>
</g>
</svg>
'''


def listen(lang):
    ru=lang=='ru'
    labels=['Ваши файлы','Ваш плейлист','Включил и слушай'] if ru else ['Your files','Your playlist','Press play. Just listen.']
    captions=['Выберите музыку','Задайте порядок','Занимайтесь своим'] if ru else ['Choose the music','Set the order','Get on with your day']
    title='Три шага к вашей музыке' if ru else 'Your music in three steps'
    groups=[]
    for i,(label,caption) in enumerate(zip(labels,captions)):
        x=35+i*527
        if i==0:
            icon='<path d="M78 88h28l12 12h45v57H78Z" fill="#dae6df" stroke="#6f8e7a" stroke-width="3"/><path d="M80 109h81" stroke="#6f8e7a" stroke-width="3"/><path d="M122 119v25m0-19 17-4v19" fill="none" stroke="#456c53" stroke-width="3"/><ellipse cx="117" cy="146" rx="6" ry="4" fill="#456c53"/><ellipse cx="134" cy="142" rx="6" ry="4" fill="#456c53"/>'
        elif i==1:
            icon='<rect x="76" y="88" width="90" height="75" rx="14" fill="#dae6df" stroke="#6f8e7a" stroke-width="3"/><g stroke="#456c53" stroke-width="4" stroke-linecap="round"><path d="M92 107h8m14 0h34M92 126h8m14 0h34M92 145h8m14 0h24"/></g>'
        else:
            icon='<circle cx="121" cy="125" r="43" fill="#d5e5d9" stroke="#6f8e7a" stroke-width="3"/><path d="M110 103L143 125L110 147Z" fill="#456c53"/>'
        groups.append(f'<g transform="translate({x} 0)"><rect x="0" y="30" width="476" height="220" rx="25" fill="#f1f5f2" stroke="#c8d6cd"/>{icon}<text x="193" y="117" font-size="25" font-weight="700" fill="#284636">{escape(label)}</text><text x="193" y="153" font-size="21" fill="#617b69">{escape(caption)}</text><text x="38" y="222" font-size="15" letter-spacing="3" fill="#89a08f">0{i+1}</text></g>')
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="280" viewBox="0 0 1600 280" role="img" aria-labelledby="title desc">
<title id="title">{title}</title><desc id="desc">Original conceptual illustration of audio files, an ordered playlist, and a play button.</desc>
<rect width="1600" height="280" rx="28" fill="#e6eee8"/>
<g font-family="Arial, Helvetica, sans-serif">{''.join(groups)}</g>
<g fill="none" stroke="#779782" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M521 137h24m-8-8 8 8-8 8M1048 137h24m-8-8 8 8-8 8"/></g>
</svg>
'''

for language in ('en','ru'):
    (OUT/f'banner-{language}.svg').write_text(banner(language),encoding='utf-8')
    (OUT/f'listen-{language}.svg').write_text(listen(language),encoding='utf-8')
print('Generated original artwork: banner-en.svg, banner-ru.svg, listen-en.svg, listen-ru.svg')
