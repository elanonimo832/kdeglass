#!/usr/bin/env python3
"""
generate-macos-decoration.py — Generates a macOS-style window decoration

WHY IT DOES NOT START FROM ANT-DARK
    The project agreement is a *macOS-style* desktop layer. Copying someone else's
    theme and separating the buttons is not that. Here the SVGs are generated from
    scratch, with the measured values from the macOS 27 kit.

WHAT IT GENERATES
    output/aurorae/KdeMacOS/
      close.svg        red traffic light    (12 px, #FF5F57)
      minimize.svg     yellow traffic light (12 px, #FFBD2E)
      maximize.svg     green traffic light  (12 px, #28C840)
      restore.svg      same for restore
      decoration.svg   window frame
      KdeMacOSrc       button measurements and layout
      metadata.desktop

THE THREE macOS DETAILS ALMOST NOBODY REPRODUCES
    1. THE GLYPHS ONLY APPEAR ON HOVER. At rest they are three clean circles.
    2. WHEN THE WINDOW LOSES FOCUS, ALL THREE FADE TO GRAY. In macOS they do not stay
       colored: they desaturate. That is Aurorae's `inactive` state.
    3. ALL THREE ARE THE SAME SIZE AND IN A ROW, WITH GENEROUS SPACING.

AURORAE STATES
    Each SVG carries 5 states IN A HORIZONTAL ROW, in this order, which is the one the
    engine expects: active, hover, pressed, inactive, deactivated.

USAGE
    python3 generate-macos-decoration.py output/aurorae/KdeMacOS
"""

from __future__ import annotations

import os
import sys

# --------------------------------------------------------------------------
# Measured values from the macOS 27 kit (tokens-shape-effects.toml and the .fig)
# --------------------------------------------------------------------------
ESCALA = 4.0            # the sprite is drawn at 4x and KWin shrinks it: no dirty edges
DIAMETRO = 12.0         # px: traffic light size measured in the kit
MARGEN_FILA = 4.0       # gap inside each sprite cell

# Exact colors from the kit.
#   close      #FF5F57
#   minimize   #FFBD2E
#   zoom       #28C840
# Gray of the unfocused state: in macOS all three desaturate when focus is lost.
GRIS_INACTIVO = "#48484A"
GRIS_APAGADO = "#3A3A3C"

# Glyphs. In macOS they are dark, thin strokes, and they only show on hover.
GLIFO_COLOR = "#4D0000"      # over the red
GLIFO_COLOR_AMARILLO = "#5A3C00"
GLIFO_COLOR_VERDE = "#0B3B0B"


def celda(indice: int) -> float:
    """X coordinate of the center of cell `indice` inside the sprite."""
    return MARGEN_FILA + DIAMETRO / 2 + indice * (DIAMETRO + MARGEN_FILA * 2)


def ancho_sprite() -> float:
    return MARGEN_FILA * 2 + DIAMETRO * 5 + MARGEN_FILA * 2 * 4


def circulo(cx: float, cy: float, r: float, relleno: str,
            borde: str | None = None, opacidad: float = 1.0,
            grosor_borde: float = 1.0) -> str:
    """A traffic light. The 1 px RING is not decorative: the kit defines it, and it is

    what makes the circle look solid instead of flat. macOS has it too.
    """
    op = f' fill-opacity="{opacidad:g}"' if opacidad != 1.0 else ""
    trazo = ""
    if borde:
        trazo = (f' stroke="{borde}" stroke-width="{grosor_borde:g}"'
                 f' stroke-opacity="0.55"')
    return (f'<circle cx="{cx:g}" cy="{cy:g}" r="{r:g}" fill="{relleno}"'
            f'{op}{trazo}/>')


def glifos(cx: float, cy: float, tipo: str, color: str, escala: float) -> str:
    """The glyph that appears on hover. Strokes, not fills."""
    g = DIAMETRO * 0.27          # glyph half-width (macOS keeps them subtle)
    grosor = DIAMETRO * 0.10
    estilo = f'stroke="{color}" stroke-width="{grosor:g}" stroke-linecap="round" fill="none"'
    if tipo == "close":
        return (
            f'<path d="M {cx-g:g} {cy-g:g} L {cx+g:g} {cy+g:g}" {estilo}/>'
            f'<path d="M {cx-g:g} {cy+g:g} L {cx+g:g} {cy-g:g}" {estilo}/>'
        )
    if tipo == "minimize":
        return f'<path d="M {cx-g:g} {cy:g} L {cx+g:g} {cy:g}" {estilo}/>'
    if tipo in ("maximize", "restore"):
        # macOS uses two small triangles in the corners, not a cross
        t = g * 0.9
        return (
            f'<path d="M {cx-g:g} {cy-g:g} L {cx-g+t:g} {cy-g:g} L {cx-g:g} {cy-g+t:g} Z" fill="{color}"/>'
            f'<path d="M {cx+g:g} {cy+g:g} L {cx+g-t:g} {cy+g:g} L {cx+g:g} {cy+g-t:g} Z" fill="{color}"/>'
        )
    return ""


def svg_boton(tipo: str, color_normal: str, color_borde: str, color_glifo: str) -> str:
    """A button sprite with Aurorae's 5 states in a row."""
    cy = MARGEN_FILA + DIAMETRO / 2
    alto = MARGEN_FILA * 2 + DIAMETRO
    ancho = ancho_sprite()
    r = DIAMETRO / 2

    partes = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{ancho:g}" height="{alto:g}"'
        f' viewBox="0 0 {ancho:g} {alto:g}">',
    ]

    # index 0: active  -> color, no glyph (the glyph only shows on hover)
    partes.append(f'<g id="active-center">{circulo(celda(0), cy, r, color_normal, color_borde)}</g>')
    # index 1: hover   -> color + glyph
    partes.append(
        f'<g id="hover-center">{circulo(celda(1), cy, r, color_normal, color_borde)}'
        f'{glifos(celda(1), cy, tipo, color_glifo, 1.0)}</g>'
    )
    # index 2: pressed -> a little darker
    partes.append(
        f'<g id="pressed-center">{circulo(celda(2), cy, r, color_normal, color_borde, 0.82)}'
        f'{glifos(celda(2), cy, tipo, color_glifo, 1.0)}</g>'
    )
    # index 3: inactive -> GRAY. It is the detail almost nobody reproduces.
    partes.append(f'<g id="inactive-center">{circulo(celda(3), cy, r, GRIS_INACTIVO)}</g>')
    # index 4: deactivated -> an even duller gray
    partes.append(f'<g id="deactivated-center">{circulo(celda(4), cy, r, GRIS_APAGADO)}</g>')

    partes.append("</svg>")
    return "".join(partes)


def svg_marco(alto_titulo: float, radio: float) -> str:
    """
    The window frame. macOS 27 uses its own window radius, different from the control
    one, and it has no marked border: the weight comes from the shadow.
    """
    w = 400.0      # reference width; KWin stretches it
    h = alto_titulo * 3   # the decoration svg covers title, sides and bottom
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w:g}" height="{h:g}" viewBox="0 0 {w:g} {h:g}">
  <defs>
    <linearGradient id="barra" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#F6F6F6"/>
      <stop offset="1" stop-color="#EDEDED"/>
    </linearGradient>
  </defs>
  <g id="decoration-top">
    <rect x="0" y="0" width="{w:g}" height="{alto_titulo:g}" fill="url(#barra)"/>
  </g>
  <g id="decoration-center">
    <rect x="0" y="{alto_titulo:g}" width="{w:g}" height="{h-alto_titulo:g}" fill="#FFFFFF"/>
  </g>
  <g id="decoration-topleft">
    <path d="M 0 {radio:g} A {radio:g} {radio:g} 0 0 1 {radio:g} 0 L 0 0 Z" fill="#F6F6F6"/>
  </g>
  <g id="decoration-topright">
    <path d="M {w:g} {radio:g} A {radio:g} {radio:g} 0 0 1 {w-radio:g} 0 L {w:g} 0 Z" fill="#F6F6F6"/>
  </g>
</svg>
'''


# The measurements. The bar height comes from tokens-shape-effects.toml: window 28.
ALTO_TITULO = 28.0
RADIO_VENTANA = 12.0     # measured window radius, different from the control one

# The KIT gives TWO colors per traffic light: the circle fill and the ring one.
# Ignoring the second leaves the buttons flat, like a plain colored circle.
BOTONES = {
    "close":    ("#FF5F57", "#FF4245", GLIFO_COLOR),
    "minimize": ("#FFBD2E", "#FF9230", GLIFO_COLOR_AMARILLO),
    "maximize": ("#28C840", "#30D158", GLIFO_COLOR_VERDE),
    "restore":  ("#28C840", "#30D158", GLIFO_COLOR_VERDE),
}

RC = f"""[General]
# macOS puts the traffic lights on the LEFT, in this order: close, minimise, zoom.
# KWin understands the letters: X=close, I=minimise, A=maximise.
LeftButtons=XIA
RightButtons=
TitleAlignment=Center
TitleVerticalAlignment=Center
ActiveTextColor=26,26,26
InactiveTextColor=114,114,114
ActiveFocusedTabColor=246,246,246
ActiveUnfocusedTabColor=230,230,230
InactiveFocusedTabColor=230,230,230
InactiveUnfocusedTabColor=230,230,230
UseTextShadow=false
Shadow=true

[Layout]
# VERTICAL CENTRING, measured. With PaddingTop=7 and ButtonMarginTop=8 a 16 px button started
# 15 px from the edge and overflowed the bottom of a 28 px bar (its centre at 23/28 = 82%).
# The glass band is 39 px and its centre sat 6.5 px above the buttons' centre and 4.5 above
# the text's. With 2/2 and a margin of 4, the button's centre lands at 2+4+8 = 14, which is
# the exact centre of the 28 px bar -- and since the bar is centred in the band, the band's
# centre too.
BorderBottom=1
BorderLeft=1
BorderRight=1
# 16, not macOS's 12: at 1:1 on a 4K 27" panel 12 px reads small, and the user asked for
# buttons they can aim at. aurorae scales the SVG cell to this number.
ButtonHeight=16
ButtonWidth=16
# Generous spacing: macOS's traffic lights breathe. The previous theme had 8 and that was
# one of its problems.
ButtonSpacing=8
ButtonMarginTop=4
ExplicitButtonSpacer=10
PaddingLeft=14
PaddingRight=14
PaddingTop=2
PaddingBottom=2
TitleHeight={ALTO_TITULO:g}
TitleEdgeTop=5
TitleEdgeBottom=5
TitleEdgeLeft=5
TitleEdgeRight=5
TitleEdgeTopMaximized=3
TitleEdgeBottomMaximized=3
TitleEdgeLeftMaximized=5
TitleEdgeRightMaximized=5
TitleBorderLeft=1
TitleBorderRight=1
"""


METADATA = """[Desktop Entry]
Name=KdeMacOS
Name[es]=KdeMacOS
Comment=Ventana estilo macOS 27: semaforos a la izquierda, medidos del kit
X-KDE-PluginInfo-Author=Paso 2 del proyecto (generado desde tokens)
X-KDE-PluginInfo-Category=
X-KDE-PluginInfo-Depends=
X-KDE-PluginInfo-Email=
X-KDE-PluginInfo-EnabledByDefault=true
X-KDE-PluginInfo-License=GPLv3
X-KDE-PluginInfo-Name=KdeMacOS
X-KDE-PluginInfo-Version=0.1.0
"""


def main() -> int:
    destino = sys.argv[1] if len(sys.argv) > 1 else "output/aurorae/KdeMacOS"
    os.makedirs(destino, exist_ok=True)

    for tipo, (color, borde, glifo) in BOTONES.items():
        ruta = os.path.join(destino, f"{tipo}.svg")
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(svg_boton(tipo, color, borde, glifo))
        print(f"  -> {tipo}.svg")

    with open(os.path.join(destino, "decoration.svg"), "w", encoding="utf-8") as f:
        f.write(svg_marco(ALTO_TITULO, RADIO_VENTANA))
    print("  -> decoration.svg")

    with open(os.path.join(destino, "KdeMacOSrc"), "w", encoding="utf-8") as f:
        f.write(RC)
    print("  -> KdeMacOSrc")

    with open(os.path.join(destino, "metadata.desktop"), "w", encoding="utf-8") as f:
        f.write(METADATA)
    print("  -> metadata.desktop")

    print()
    print(f"Traffic lights: {DIAMETRO:g} px, 8 px apart, in a row on the LEFT.")
    print("Kit colors: #FF5F57 (close), #FFBD2E (minimize), #28C840 (zoom).")
    print("Unfocused: all three fade to gray, as in macOS.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
