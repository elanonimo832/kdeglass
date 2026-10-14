#!/usr/bin/env python3
"""
consolidate-tokens.py — Merges the five axes into a single tokens.toml

WHY
    The brief asked for «a tokens.json with the design system… From it the three are
    GENERATED». This is that file, in TOML (better for diffing than JSON) and with the
    five axes the brief did not have complete:

      1. color      — 61 measured tokens, in light and dark
      2. shape      — radii, squircle, shadows, hairline border
      3. metrics    — control sizes per size (Mini..XL)
      4. typography — the macOS scale from the official HIG
      5. material   — Liquid Glass and the blurs

    And a sixth section, [_procedencia], which says where each axis comes from. Without
    that, a token is a figure with no origin.

USAGE
    python3 consolidate-tokens.py tokens/ tokens.toml
"""

from __future__ import annotations

import os
import re
import sys
import tomllib
from datetime import date


def leer(p: str) -> dict:
    with open(p, "rb") as f:
        return tomllib.load(f)


def serializar(obj, prefijo: str = "") -> list[str]:
    """Dumps a nested dict as TOML, with the leaves sorted."""
    lineas = []
    simples = {k: v for k, v in obj.items() if not isinstance(v, dict)}
    tablas = {k: v for k, v in obj.items() if isinstance(v, dict)}

    for k in sorted(simples):
        v = simples[k]
        if isinstance(v, bool):
            lineas.append(f"{k} = {'true' if v else 'false'}")
        elif isinstance(v, (int, float)):
            lineas.append(f"{k} = {v:g}")
        elif isinstance(v, str):
            esc = v.replace("\\", "\\\\").replace('"', '\\"')
            lineas.append(f'{k} = "{esc}"')
        else:
            lineas.append(f'{k} = "{v}"')

    for k in sorted(tablas):
        ruta = f"{prefijo}{k}"
        lineas.append("")
        lineas.append(f"[{ruta}]")
        lineas.extend(serializar(tablas[k], f"{ruta}."))
    return lineas


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    dir_tokens, destino = sys.argv[1], sys.argv[2]

    color = leer(os.path.join(dir_tokens, "tokens-colors.toml"))
    forma = leer(os.path.join(dir_tokens, "tokens-shape-effects.toml"))
    metricas = leer(os.path.join(dir_tokens, "tokens-sizes.toml"))
    tipo = leer(os.path.join(dir_tokens, "tokens-typography_macos.toml"))
    kit = leer(os.path.join(dir_tokens, "tokens-kit.toml"))

    # We remove the meta from each partial: the consolidated one has its own.
    for d in (color, forma, metricas, tipo, kit):
        d.pop("_meta", None)
    # And the leftovers of the export that are not design.
    for basura in ("mode", "string"):
        color.pop(basura, None)

    L = [
        "# tokens.toml — EL SISTEMA DE DISENO. GENERADO, no editar a mano.",
        "#",
        "# Es el fichero que pedia el brief: la fuente unica de verdad de la que se",
        "# generan los esquemas de KDE, el CSS de GTK, el Tokens.h del QStyle y la",
        "# configuracion del efecto KWin.",
        "#",
        f"# Fecha de consolidacion: {date.today().isoformat()}",
        "#",
        "# LOS CINCO EJES",
        "#   [color]      61 tokens medidos, claro y oscuro, con alfa exacto",
        "#   [forma]      radios, squircle, sombras de ventana, borde capilar",
        "#   [metricas]   tamanos de control por tamano (Mini..XL)",
        "#   [tipografia] la escala de macOS, de las HIG oficiales de Apple",
        "#   [material]   Liquid Glass y la escala de difuminados",
        "#",
        "# REGLA DE PROCEDENCIA: cada eje lleva su origen en [_procedencia]. Los valores",
        "# son MEDIDOS o PUBLICADOS, no inventados. Donde no hay dato, no hay token.",
        "#",
        "# AVISO sobre la fuente tipografica: macOS usa SF Pro, que Apple no permite",
        "# redistribuir. El proyecto usa Inter. Los tamanos, interlineados y pesos de",
        "# [tipografia] se aplican tal cual; el TRACKING es de SF Pro y con otra familia",
        "# es una aproximacion de partida.",
        "",
        "[_meta]",
        'nombre = "macOS Desktop Layer"',
        'referencia = "macOS 27 Golden Gate"',
        f'fecha = "{date.today().isoformat()}"',
        'unidades = "puntos, salvo donde se indique px"',
        "",
        "# ===========================================================================",
        "# PROCEDENCIA: de donde sale cada eje. Cada valor es trazable a una fuente.",
        "# ===========================================================================",
        "[_procedencia]",
        'color = "figma: export de Variables (Colors.zip), 61 tokens, claro y oscuro"',
        'forma = "fig: propiedades de nodo, 19011 nodos (radios, sombras, borde)"',
        'metricas = "figma: export de Variables (Sizes.zip), 5 tamanos de control"',
        'tipografia = "Apple HIG oficiales (typography.json), tabla macOS built-in text styles"',
        'material = "fig: efecto GLASS y nodos de difuminado"',
        'squircle = "fig: cornerSmoothing = 0.6, en 2244 nodos"',
        "",
        "# ===========================================================================",
        "# 1. COLOR",
        "# ===========================================================================",
        "[color]",
        "# 61 tokens del kit. `claro`/`oscuro` es el valor por apariencia. Los tokens",
        "# cuyo valor es IGUAL en ambos modos llevan una sola pareja hex/alfa.",
        "# El patron clave es el VELO: el texto es blanco o negro con alfa decreciente,",
        "# no un gris propio. Es lo que hace que funcione sobre cualquier fondo.",
    ]
    L.extend(serializar(color, "color."))

    L += [
        "",
        "# ===========================================================================",
        "# 2. FORMA: radios, squircle, sombras y borde capilar",
        "# ===========================================================================",
        "[forma]",
        "# Los radios NO son un valor unico: escalan con el tamano del control.",
    ]
    L.extend(serializar(forma, "forma."))

    L += [
        "",
        "# ===========================================================================",
        "# 3. METRICAS de control, por tamano",
        "# ===========================================================================",
        "[metricas]",
        "# Mini, Small, Medium, Large, XL. Medium es el tamano por defecto del sistema.",
        "# `global.radius` = 4/5/6/7/9 confirma que el radio escala con el control.",
    ]
    L.extend(serializar(metricas, "metricas."))

    L += [
        "",
        "# ===========================================================================",
        "# 4. TIPOGRAFIA de macOS (HIG oficiales)",
        "# ===========================================================================",
        "[tipografia]",
        "# 11 estilos con tamano, interlineado, peso y tracking. macOS NO tiene Dynamic",
        "# Type: hay UNA escala, no doce como en iOS.",
    ]
    L.extend(serializar(tipo, "tipografia."))

    L += [
        "",
        "# ===========================================================================",
        "# 5. MATERIAL: Liquid Glass",
        "# ===========================================================================",
        "[material]",
        "# El material del brief, parametrizado. Tiene SIETE parametros, no tres:",
        "# refraction y dispersion no aparecian en el brief y son la diferencia entre",
        "# un cristal esmerilado y un vidrio.",
    ]
    L.extend(serializar(kit, "material."))

    L.append("")

    with open(destino, "w", encoding="utf-8") as f:
        f.write("\n".join(L))
    print(f"Wrote {destino}: {len(L)} lines")
    return 0


if __name__ == "__main__":
    sys.exit(main())
