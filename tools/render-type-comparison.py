#!/usr/bin/env python3
"""
render-type-comparison.py — M4's evidence: the SAME text at KDE's default scale and at macOS's.

WHAT THIS IS FOR
    docs/ROADMAP.md's "done when" for M4 asks for "a comparison of rendered text in evidence/".
    A comparison has to be MEASURED with a renderer, not drawn by hand: this renders the same
    strings twice, with a real font file through a real shaper (PIL/FreeType), and prints the
    advance widths so the difference is a NUMBER and not an opinion.

THE TWO SCALES, AND WHY THEY ARE THESE
    * macOS: the token sizes IN PIXELS (Body 13, Headline 13 bold). The HIG draws its styles at
      1 pt = 1 px and macOS has no Dynamic Type, so the scale is fixed -- which is what the
      generator writes into kdeglobals (`Inter,-1,13,5,50,...`, the pixel field).
    * KDE's default: `Noto Sans,12` POINTS. KDE renders points at its font DPI, which is 96 on
      this machine (no `forceFontDPI` key, measured), so 12 pt = 12 * 96/72 = 16 px. That is what
      the user has today, and it is what the type scale has to replace.
    The ratio is not a detail: 16/13 = 1.23, so the same sentence is a quarter wider at KDE's
    default size than on macOS.

HONEST LIMIT, AND IT IS IN THE PICTURE
    Inter is NOT installed on this machine (measured: `fc-list | grep -i inter` is empty), so both
    rows are rendered with the family fontconfig substitutes, Noto Sans. The comparison is
    therefore about the SCALE, not about the typeface: the shapes are identical by construction and
    only the size changes. Install the real family with `sudo pacman -S inter-font` and re-run this
    script to see the typeface too.

USAGE
    python3 tools/render-type-comparison.py [output.png]
"""

from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw, ImageFont

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EVIDENCIA = os.path.join(RAIZ, "evidence", "2026-10-15-m4-text-scale.png")

REGULAR = "/usr/share/fonts/noto/NotoSans-Regular.ttf"
BOLD = "/usr/share/fonts/noto/NotoSans-Bold.ttf"

# The strings are the ones an interface actually shows, so the measurement is not of a glyph soup.
MUESTRAS = [
    ("Body / interface text", "The quick brown fox jumps over the lazy dog"),
    ("Menu / menuFont", "Open Recent…    Save a Copy    Export as PDF"),
    ("Smallest / smallestReadableFont", "18 folders, 9 files (127.0 KiB)"),
]

FONDO = (250, 250, 250)
TEXTO = (38, 38, 38)          # Colors:Window ForegroundNormal, from the generated scheme
GRIS = (140, 140, 140)
AZUL = (0, 136, 255)          # the scheme's DecorationFocus: the accent
ALTO = 46


def medidas(fuente: ImageFont.FreeTypeFont, texto: str) -> tuple[int, int]:
    """(advance width, ink height) of a string, MEASURED by the shaper."""
    caja = fuente.getbbox(texto)
    return int(round(fuente.getlength(texto))), caja[3] - caja[1]


def fila(im: Image.Image, d: ImageDraw.ImageDraw, y: int, etiqueta: str, texto: str,
         tam: int, negrita: bool = False) -> int:
    """One labelled sample. Returns the measured advance width so it can be printed."""
    f_etiqueta = ImageFont.truetype(REGULAR, 11)
    f_texto = ImageFont.truetype(BOLD if negrita else REGULAR, tam)
    d.text((16, y + 4), etiqueta, font=f_etiqueta, fill=GRIS)
    ancho, _ = medidas(f_texto, texto)
    d.text((16, y + 20), texto, font=f_texto, fill=TEXTO)
    d.text((im.width - 150, y + 22), f"{ancho} px", font=f_etiqueta, fill=AZUL)
    return ancho


def panel(im: Image.Image, d: ImageDraw.ImageDraw, y: int, titulo: str, tam: int,
          titulo_tam: int, negrita: bool) -> tuple[int, list[int]]:
    """A titled panel with the three samples. Returns (height used, widths measured)."""
    f_titulo = ImageFont.truetype(BOLD, 13)
    d.text((16, y + 8), titulo, font=f_titulo, fill=AZUL)
    y += 30
    anchos = []
    for etiqueta, texto in MUESTRAS:
        anchos.append(fila(im, d, y, etiqueta, texto, tam, negrita))
        y += ALTO
    # The window title, which kdeglobals carries in [WM] and the generator writes bold.
    anchos.append(fila(im, d, y, "Window title / [WM] activeFont", "effect-kwin : fish — Konsole",
                       titulo_tam, True))
    y += ALTO
    return y, anchos


def main() -> int:
    destino = sys.argv[1] if len(sys.argv) > 1 else EVIDENCIA
    im = Image.new("RGB", (760, 460), FONDO)
    d = ImageDraw.Draw(im)

    # KDE's default first: it is what the user has, and the "before" of the comparison.
    y, anchos_kde = panel(im, d, 10, "KDE DEFAULT  ·  Noto Sans 12 pt @ 96 DPI = 16 px",
                          16, 16, False)
    d.line((12, y + 4, im.width - 12, y + 4), fill=(210, 210, 210), width=1)
    y2, anchos_mac = panel(im, d, y + 14, "macOS SCALE (M4)  ·  Body 13 px, title 13 px bold",
                           13, 13, False)

    d.text((16, y2 + 10),
           "Both rows use the SAME font file (Noto Sans): Inter is not installed, so this compares",
           font=ImageFont.truetype(REGULAR, 11), fill=GRIS)
    d.text((16, y2 + 26),
           "the SCALE, not the typeface. Install it with: sudo pacman -S inter-font",
           font=ImageFont.truetype(REGULAR, 11), fill=GRIS)

    os.makedirs(os.path.dirname(destino), exist_ok=True)
    im.save(destino)

    # The numbers, so the evidence is auditable without opening the PNG.
    print("measured advance widths (px), KDE default vs macOS scale:")
    for (etiqueta, _), a, b in zip(MUESTRAS + [("Window title", "")], anchos_kde, anchos_mac):
        print(f"  {etiqueta:34s} {a:4d} -> {b:4d}   ratio {b / a:.3f}")
    print(f"  -> {destino}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
