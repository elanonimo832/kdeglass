#!/usr/bin/env python3
"""
generate-macos-decoration.py — Genera una decoracion de ventana estilo macOS

POR QUE NO SE PARTE DE ANT-DARK
    El acuerdo del proyecto es una capa de escritorio *estilo macOS*. Copiar el tema
    de otro y separar los botones no es eso. Aqui se generan los SVG desde cero, con
    los valores medidos del kit de macOS 27.

LO QUE GENERA
    output/aurorae/KdeMacOS/
      close.svg        semaforo rojo     (12 px, #FF5F57)
      minimize.svg     semaforo amarillo (12 px, #FFBD2E)
      maximize.svg     semaforo verde    (12 px, #28C840)
      restore.svg      idem para restaurar
      decoration.svg   marco de la ventana
      KdeMacOSrc       medidas y disposicion de los botones
      metadata.desktop

LOS TRES DETALLES DE macOS QUE CASI NADIE REPRODUCE
    1. LOS GLIFOS SOLO APARECEN AL PASAR EL RATON. En reposo son tres circulos limpios.
    2. CUANDO LA VENTANA PIERDE EL FOCO, LOS TRES SE APAGAN A GRIS. En macOS no se
       quedan de color: se desaturan. Ese es el estado `inactive` de Aurorae.
    3. LAS TRES SON DEL MISMO TAMANO Y ESTAN EN FILA, CON SEPARACION GENEROSA.

ESTADOS DE AURORAE
    Cada SVG lleva 5 estados EN FILA HORIZONTAL, en este orden, que es el que espera
    el motor: active, hover, pressed, inactive, deactivated.

USO
    python3 generate-macos-decoration.py output/aurorae/KdeMacOS
"""

from __future__ import annotations

import os
import sys

# --------------------------------------------------------------------------
# Valores medidos del kit de macOS 27 (tokens-forma-efectos.toml y el .fig)
# --------------------------------------------------------------------------
ESCALA = 4.0            # el sprite se dibuja a 4x y KWin lo reduce: asi no hay bordes sucios
DIAMETRO = 12.0         # px: tamano de los semaforos medido en el kit
MARGEN_FILA = 4.0       # hueco dentro de cada celda del sprite

# Colores exactos del kit.
#   cierre     #FF5F57
#   minimizar  #FFBD2E
#   zoom       #28C840
# Gris del estado sin foco: en macOS los tres se desaturan al perder el foco.
GRIS_INACTIVO = "#48484A"
GRIS_APAGADO = "#3A3A3C"

# Glifos. En macOS son trazos oscuros y finos, y solo se ven al pasar el raton.
GLIFO_COLOR = "#4D0000"      # sobre el rojo
GLIFO_COLOR_AMARILLO = "#5A3C00"
GLIFO_COLOR_VERDE = "#0B3B0B"


def celda(indice: int) -> float:
    """Coordenada x del centro de la celda `indice` dentro del sprite."""
    return MARGEN_FILA + DIAMETRO / 2 + indice * (DIAMETRO + MARGEN_FILA * 2)


def ancho_sprite() -> float:
    return MARGEN_FILA * 2 + DIAMETRO * 5 + MARGEN_FILA * 2 * 4


def circulo(cx: float, cy: float, r: float, relleno: str,
            borde: str | None = None, opacidad: float = 1.0,
            grosor_borde: float = 1.0) -> str:
    """Un semaforo. El ARO de 1 px no es decorativo: el kit lo define, y es lo que

    hace que el circulo se vea solido en lugar de plano. macOS tambien lo lleva.
    """
    op = f' fill-opacity="{opacidad:g}"' if opacidad != 1.0 else ""
    trazo = ""
    if borde:
        trazo = (f' stroke="{borde}" stroke-width="{grosor_borde:g}"'
                 f' stroke-opacity="0.55"')
    return (f'<circle cx="{cx:g}" cy="{cy:g}" r="{r:g}" fill="{relleno}"'
            f'{op}{trazo}/>')


def glifos(cx: float, cy: float, tipo: str, color: str, escala: float) -> str:
    """El glifo que aparece al pasar el raton. Trazos, no rellenos."""
    g = DIAMETRO * 0.27          # semiancho del glifo (macOS los hace discretos)
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
        # macOS usa dos triangulos pequenos en las esquinas, no una cruz
        t = g * 0.9
        return (
            f'<path d="M {cx-g:g} {cy-g:g} L {cx-g+t:g} {cy-g:g} L {cx-g:g} {cy-g+t:g} Z" fill="{color}"/>'
            f'<path d="M {cx+g:g} {cy+g:g} L {cx+g-t:g} {cy+g:g} L {cx+g:g} {cy+g-t:g} Z" fill="{color}"/>'
        )
    return ""


def svg_boton(tipo: str, color_normal: str, color_borde: str, color_glifo: str) -> str:
    """Un sprite de boton con los 5 estados de Aurorae en fila."""
    cy = MARGEN_FILA + DIAMETRO / 2
    alto = MARGEN_FILA * 2 + DIAMETRO
    ancho = ancho_sprite()
    r = DIAMETRO / 2

    partes = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{ancho:g}" height="{alto:g}"'
        f' viewBox="0 0 {ancho:g} {alto:g}">',
    ]

    # indice 0: active  -> color, sin glifo (el glifo solo sale al pasar el raton)
    partes.append(f'<g id="active-center">{circulo(celda(0), cy, r, color_normal, color_borde)}</g>')
    # indice 1: hover   -> color + glifo
    partes.append(
        f'<g id="hover-center">{circulo(celda(1), cy, r, color_normal, color_borde)}'
        f'{glifos(celda(1), cy, tipo, color_glifo, 1.0)}</g>'
    )
    # indice 2: pressed -> un poco mas oscuro
    partes.append(
        f'<g id="pressed-center">{circulo(celda(2), cy, r, color_normal, color_borde, 0.82)}'
        f'{glifos(celda(2), cy, tipo, color_glifo, 1.0)}</g>'
    )
    # indice 3: inactive -> GRIS. Es el detalle que casi nadie reproduce.
    partes.append(f'<g id="inactive-center">{circulo(celda(3), cy, r, GRIS_INACTIVO)}</g>')
    # indice 4: deactivated -> gris mas apagado todavia
    partes.append(f'<g id="deactivated-center">{circulo(celda(4), cy, r, GRIS_APAGADO)}</g>')

    partes.append("</svg>")
    return "".join(partes)


def svg_marco(alto_titulo: float, radio: float) -> str:
    """
    El marco de la ventana. macOS 27 usa un radio de ventana propio, distinto del de
    control, y no lleva borde marcado: el peso lo da la sombra.
    """
    w = 400.0      # ancho de referencia; KWin lo estira
    h = alto_titulo * 3   # el svg de decoracion cubre titulo, lados y base
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


# Las medidas. El alto de la barra sale de tokens-forma-efectos.toml: ventana 28.
ALTO_TITULO = 28.0
RADIO_VENTANA = 12.0     # radio de ventana medido, distinto del de control

# El KIT da DOS colores por semaforo: el relleno del circulo y el del aro.
# Ignorar el segundo deja los botones planos, como un circulo de color sin mas.
BOTONES = {
    "close":    ("#FF5F57", "#FF4245", GLIFO_COLOR),
    "minimize": ("#FFBD2E", "#FF9230", GLIFO_COLOR_AMARILLO),
    "maximize": ("#28C840", "#30D158", GLIFO_COLOR_VERDE),
    "restore":  ("#28C840", "#30D158", GLIFO_COLOR_VERDE),
}

RC = f"""[General]
# macOS pone los semaforos a la IZQUIERDA, en este orden: cerrar, minimizar, zoom.
# El orden de las letras lo entiende KWin: X=cerrar, I=minimizar, A=maximizar.
LeftButtons=XIA
RightButtons=
TitleAlignment=Center
TitleVerticalAlignment=Center
ActiveTextColor=64,64,64
InactiveTextColor=140,140,140
ActiveFocusedTabColor=246,246,246
ActiveUnfocusedTabColor=230,230,230
InactiveFocusedTabColor=230,230,230
InactiveUnfocusedTabColor=230,230,230
UseTextShadow=false
Shadow=true

[Layout]
BorderBottom=1
BorderLeft=1
BorderRight=1
ButtonHeight={DIAMETRO:g}
ButtonWidth={DIAMETRO:g}
# Separacion generosa: en macOS los semaforos respiran. Este era el problema del
# tema anterior, que tenia 8.
ButtonSpacing=8
ButtonMarginTop=8
ExplicitButtonSpacer=10
PaddingLeft=14
PaddingRight=14
PaddingTop=7
PaddingBottom=7
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
    print(f"Semaforos: {DIAMETRO:g} px, separacion 8 px, en fila a la IZQUIERDA.")
    print("Colores del kit: #FF5F57 (cerrar), #FFBD2E (minimizar), #28C840 (zoom).")
    print("Sin foco: los tres se apagan a gris, como en macOS.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
