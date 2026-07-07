#!/usr/bin/env python3
"""Nidhi — Kalasha identity family (the chosen mark).

Generates into design/logos/kalasha/:
  mark.svg / mark-mono.svg / mark-white.svg          script-independent pot
  icon-light.svg / icon-dark.svg / icon-tinted.svg   full-bleed app-icon art
      (mirrors design/GenerateIcons.swift: flat, full-bleed; iOS applies Liquid Glass)
  lockup-<script>.svg                                 horizontal pot + wordmark
  nidhi-<script>.svg                                  stacked pot + wordmark (from the exploration)

Re-run:  python3 design/logos/generate_kalasha.py
Text uses system Indic fonts — convert to outlines before shipping.
"""
import os

ACCENT, DEEP, SAGE, SAGE_DEEP, INK = "#6E9BD8", "#4F7FC4", "#7FC4A3", "#5BA585", "#151A22"
DARK1, DARK2 = "#121820", "#101C17"   # GenerateIcons.swift dark bg endpoints
FONT = "'Kohinoor Devanagari','Noto Sans',-apple-system,sans-serif"

SCRIPTS = [
    ("devanagari", "निधि", "hi"), ("bengali", "নিধি", "bn"), ("gujarati", "નિધિ", "gu"),
    ("gurmukhi", "ਨਿਧੀ", "pa"), ("odia", "ନିଧି", "or"), ("tamil", "நிதி", "ta"),
    ("telugu", "నిధి", "te"), ("kannada", "ನಿಧಿ", "kn"), ("malayalam", "നിധി", "ml"),
    ("urdu", "نِدھی", "ur"), ("meitei", "ꯅꯤꯙꯤ", "mni"), ("latin", "Nidhi", "en"),
]

GRAD = f"""<linearGradient id="zen" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="{ACCENT}"/><stop offset="1" stop-color="{DEEP}"/></linearGradient>"""


def pot(fill, coin1=SAGE, coin2=SAGE_DEEP, smile="#FFFFFF", smile_op="0.55", ox=0, oy=0, scale=1.0):
    """The kalasha: pot body + rim, three coins, one content smile. 260x150 box at scale 1."""
    return f"""<g transform="translate({ox},{oy}) scale({scale})">
  <path d="M 90 62 Q 84 54 92 50 L 168 50 Q 176 54 170 62 Q 196 78 196 112
           Q 196 152 130 152 Q 64 152 64 112 Q 64 78 90 62 Z" fill="{fill}"/>
  <circle cx="112" cy="34" r="8" fill="{coin1}"/>
  <circle cx="130" cy="26" r="8" fill="{coin2}"/>
  <circle cx="148" cy="34" r="8" fill="{coin1}"/>
  <path d="M 88 96 Q 130 116 172 96" stroke="{smile}" stroke-width="5"
        fill="none" opacity="{smile_op}" stroke-linecap="round"/></g>"""


def svg(vb, body, lang="und", extra=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}" lang="{lang}"{extra}>'
            f'<defs>{GRAD}</defs>{body}</svg>\n')


here = os.path.join(os.path.dirname(os.path.abspath(__file__)), "kalasha")
os.makedirs(here, exist_ok=True)
out = {}

# --- marks -----------------------------------------------------------------
out["mark.svg"] = svg("0 0 260 170", pot("url(#zen)"))
out["mark-mono.svg"] = svg("0 0 260 170", pot(INK, coin1=INK, coin2=INK, smile="#FFFFFF"))
out["mark-white.svg"] = svg("0 0 260 170",
    pot("#FFFFFF", coin1="#FFFFFF", coin2="#FFFFFF", smile=DEEP, smile_op="0.85"))

# --- app-icon art (1024, full-bleed; iOS masks/rounds it) -------------------
# pot box is 260x150 → scale 2.6 = 676 wide, centered: ox=(1024-676)/2=174, oy≈190
icon_pot = dict(ox=174, oy=190, scale=2.6)
out["icon-light.svg"] = svg("0 0 1024 1024",
    f'<linearGradient id="bg" x1="0" y1="1" x2="1" y2="0">'
    f'<stop offset="0" stop-color="{ACCENT}"/><stop offset="1" stop-color="{SAGE}"/></linearGradient>'
    f'<rect width="1024" height="1024" fill="url(#bg)"/>'
    + pot("#FFFFFF", coin1="#FFFFFF", coin2="#FFFFFF", smile=DEEP, smile_op="0.8", **icon_pot))
out["icon-dark.svg"] = svg("0 0 1024 1024",
    f'<linearGradient id="bgd" x1="0" y1="1" x2="1" y2="0">'
    f'<stop offset="0" stop-color="{DARK1}"/><stop offset="1" stop-color="{DARK2}"/></linearGradient>'
    f'<rect width="1024" height="1024" fill="url(#bgd)"/>'
    + pot("url(#zen)", smile="#FFFFFF", smile_op="0.7", **icon_pot))
out["icon-tinted.svg"] = svg("0 0 1024 1024",   # transparent; system applies tint
    pot("#C7CCD4", coin1="#C7CCD4", coin2="#C7CCD4", smile="#FFFFFF", smile_op="0.9", **icon_pot))

# --- lockups (horizontal) & stacked per script ------------------------------
for slug, word, lang in SCRIPTS:
    anchor, tx = ("end", 470) if lang == "ur" else ("start", 200)
    out[f"lockup-{slug}.svg"] = svg("0 0 500 170",
        pot("url(#zen)", scale=0.95, oy=8)
        + f'<text x="{tx}" y="108" font-family="{FONT}" font-size="58" font-weight="600" '
          f'fill="{INK}" text-anchor="{anchor}">{word}</text>', lang)
    out[f"nidhi-{slug}.svg"] = svg("0 0 260 220",
        pot("url(#zen)")
        + f'<text x="130" y="196" font-family="{FONT}" font-size="40" font-weight="600" '
          f'fill="{INK}" text-anchor="middle">{word}</text>', lang)

for name, content in out.items():
    with open(os.path.join(here, name), "w") as f:
        f.write(content)
print(f"wrote {len(out)} files to design/logos/kalasha/")
