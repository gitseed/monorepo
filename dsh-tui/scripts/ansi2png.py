#!/usr/bin/env python3
"""Render `tmux capture-pane -e -p` output (per-row ANSI with SGR only) to a
PNG, so the agent iterating on TUI styling can look at actual frames.

Usage: ansi2png.py <in.ansi> <out.png> [cols]
"""

import re
import sys

from PIL import Image, ImageDraw, ImageFont

# A dark-terminal palette (close to common defaults). Index 0-15, then the
# xterm 256 cube/grayscale are computed.
BASE16 = [
    (40, 44, 52), (224, 108, 117), (152, 195, 121), (229, 192, 123),
    (97, 175, 239), (198, 120, 221), (86, 182, 194), (171, 178, 191),
    (92, 99, 112), (224, 108, 117), (152, 195, 121), (229, 192, 123),
    (97, 175, 239), (198, 120, 221), (86, 182, 194), (255, 255, 255),
]
DEFAULT_FG = (171, 178, 191)
DEFAULT_BG = (30, 34, 39)


def color256(n):
    if n < 16:
        return BASE16[n]
    if n < 232:
        n -= 16
        r, g, b = n // 36, (n % 36) // 6, n % 6
        conv = lambda v: 0 if v == 0 else 55 + v * 40
        return (conv(r), conv(g), conv(b))
    v = 8 + (n - 232) * 10
    return (v, v, v)


class Cell:
    __slots__ = ("ch", "fg", "bg", "bold", "faint", "italic")

    def __init__(self, ch=" ", fg=None, bg=None, bold=False, faint=False, italic=False):
        self.ch, self.fg, self.bg = ch, fg, bg
        self.bold, self.faint, self.italic = bold, faint, italic


SGR_RE = re.compile(r"\x1b\[([0-9;:]*)m")
OTHER_ESC_RE = re.compile(r"\x1b(\][^\a\x1b]*(\a|\x1b\\)|[\[][0-9;?]*[a-lnzA-Z]|[()][A-Z0-9])")


def parse(text, cols):
    rows = []
    fg = bg = None
    bold = faint = italic = False
    for raw in text.split("\n"):
        raw = OTHER_ESC_RE.sub(lambda m: m.group(0) if m.group(0).endswith("m") else "", raw)
        row = []
        i = 0
        while i < len(raw):
            m = SGR_RE.match(raw, i)
            if m:
                parts = [p or "0" for p in re.split("[;:]", m.group(1))] or ["0"]
                j = 0
                while j < len(parts):
                    p = int(parts[j])
                    if p == 0:
                        fg = bg = None
                        bold = faint = italic = False
                    elif p == 1:
                        bold = True
                    elif p == 2:
                        faint = True
                    elif p == 3:
                        italic = True
                    elif p in (22, 23):
                        bold = faint = italic = False
                    elif 30 <= p <= 37:
                        fg = BASE16[p - 30]
                    elif p == 38 and j + 1 < len(parts):
                        if parts[j + 1] == "5":
                            fg = color256(int(parts[j + 2])); j += 2
                        elif parts[j + 1] == "2":
                            fg = tuple(int(x) for x in parts[j + 2:j + 5]); j += 4
                    elif p == 39:
                        fg = None
                    elif 40 <= p <= 47:
                        bg = BASE16[p - 40]
                    elif p == 48 and j + 1 < len(parts):
                        if parts[j + 1] == "5":
                            bg = color256(int(parts[j + 2])); j += 2
                        elif parts[j + 1] == "2":
                            bg = tuple(int(x) for x in parts[j + 2:j + 5]); j += 4
                    elif p == 49:
                        bg = None
                    elif 90 <= p <= 97:
                        fg = BASE16[p - 90 + 8]
                    elif 100 <= p <= 107:
                        bg = BASE16[p - 100 + 8]
                    j += 1
                i = m.end()
                continue
            ch = raw[i]
            if ch != "\x1b":
                row.append(Cell(ch, fg, bg, bold, faint, italic))
            i += 1
        rows.append(row[:cols])
    return rows


def render(rows, cols, out_path):
    cw, chh = 9, 18
    font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 14, index=0)
    bold_font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 14, index=1)
    img = Image.new("RGB", (cols * cw + 16, len(rows) * chh + 16), DEFAULT_BG)
    draw = ImageDraw.Draw(img)
    for y, row in enumerate(rows):
        for x, cell in enumerate(row):
            px, py = 8 + x * cw, 8 + y * chh
            if cell.bg:
                draw.rectangle([px, py, px + cw, py + chh], fill=cell.bg)
            if cell.ch != " ":
                fg = cell.fg or DEFAULT_FG
                if cell.faint:
                    fg = tuple((c + DEFAULT_BG[k]) // 2 for k, c in enumerate(fg))
                draw.text((px, py), cell.ch, fill=fg, font=bold_font if cell.bold else font)
    img.save(out_path)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    cols = int(sys.argv[3]) if len(sys.argv) > 3 else 100
    with open(src, encoding="utf-8", errors="replace") as f:
        rows = parse(f.read(), cols)
    render(rows, cols, dst)
    print(dst)


if __name__ == "__main__":
    main()
