#!/usr/bin/env python3
"""
extract-fig.py — Pulls from the .fig document the values that were NOT variables

WHY IT IS NEEDED
    Figma's Variables export only carries what was declared as a variable. Radii,
    effects, stroke colors and text styles live in the NODE PROPERTIES, so they do not
    show up anywhere. Here they are.

WHAT IT EXTRACTS
    1. cornerRadius + cornerSmoothing   -> the radius and the SQUIRCLE (the superellipse)
    2. effects                          -> shadows, blurs, effect radii
    3. fillPaints / strokePaints        -> the hairline border and translucency (alpha)
    4. fontSize / lineHeight / letterSpacing / fontName -> real text styles
    5. stackSpacing / padding           -> layout spacings

    For each magnitude it groups by node name, which is what makes it possible to
    identify which control each value belongs to (e.g. a "Window" with radius 10).

USAGE
    python3 extract-fig.py kit.json output/
"""

from __future__ import annotations

import collections
import json
import os
import re
import sys
from datetime import date

# Names of interest for the window chrome and the controls.
RELEVANTES = re.compile(
    r"window|titlebar|title bar|toolbar|sidebar|button|checkbox|radio|switch|toggle|"
    r"slider|segmented|field|search|menu|popover|sheet|panel|tab|stepper|combo|"
    r"dialog|alert|tooltip|scrollbar|progress|badge|card|glass|material|control|"
    r"corner|background|separator|divider|stroke|border",
    re.I,
)


def tipo_de(n) -> str:
    t = n.get("type")
    if isinstance(t, dict):
        return t.get("name") or "?"
    return str(t)


def num(x):
    if isinstance(x, dict):
        for k in ("value", "val"):
            if k in x:
                return num(x[k])
        return None
    if isinstance(x, (int, float)):
        return float(x)
    return None


def paints_a_texto(paints) -> str:
    """Summarizes a list of paints: color + alpha + opacity type."""
    if not isinstance(paints, list):
        return ""
    partes = []
    for p in paints[:3]:
        if not isinstance(p, dict):
            continue
        tipo = p.get("type")
        if isinstance(tipo, dict):
            tipo = tipo.get("name")
        col = p.get("color") or p.get("authoredColor") or {}
        hexv = ""
        if isinstance(col, dict):
            hexv = col.get("hex") or ""
            if not hexv and all(k in col for k in ("r", "g", "b")):
                hexv = "#%02X%02X%02X" % tuple(
                    int(round(float(col[k]) * 255)) for k in ("r", "g", "b")
                )
        alfa = col.get("a") if isinstance(col, dict) else None
        op = p.get("opacity")
        if isinstance(op, dict):
            op = op.get("value")
        trozo = f"{tipo or '?'}"
        if hexv:
            trozo += f" {hexv}"
        if alfa is not None:
            trozo += f" a={round(float(alfa),4):g}"
        if op is not None:
            trozo += f" op={round(float(op),4):g}"
        partes.append(trozo)
    return " | ".join(partes)


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    origen, destino = sys.argv[1], sys.argv[2]
    os.makedirs(destino, exist_ok=True)

    print(f"Reading {origen} ...")
    d = json.load(open(origen))
    nodos = d.get("nodeChanges", [])
    print(f"  {len(nodos)} nodes")

    # ---- accumulators: (magnitude) -> Counter[(normalized_name, value)] ----
    radios = collections.Counter()
    smoothing = collections.Counter()
    efectos = collections.Counter()
    trazos = collections.Counter()
    textos = collections.Counter()
    espaciados = collections.Counter()

    for n in nodos:
        nombre = (n.get("name") or "").strip()
        t = tipo_de(n)

        # 1) radii
        cr = num(n.get("cornerRadius"))
        cs = num(n.get("cornerSmoothing"))
        if cr is not None and cr > 0:
            radios[(nombre[:48], round(cr, 2))] += 1
            if cs:
                smoothing[round(cs, 3)] += 1
        for campo in ("rectangleTopLeftCornerRadius", "rectangleTopRightCornerRadius",
                      "rectangleBottomLeftCornerRadius", "rectangleBottomRightCornerRadius"):
            v = num(n.get(campo))
            if v:
                radios[(f"{nombre[:40]}[esquina]", round(v, 2))] += 1

        # 2) effects (shadows, blurs)
        for e in (n.get("effects") or []):
            if not isinstance(e, dict):
                continue
            et = e.get("type")
            if isinstance(et, dict):
                et = et.get("name")
            radio = num(e.get("radius"))
            off = e.get("offset")
            dx = dy = None
            if isinstance(off, dict):
                dx, dy = num(off.get("x")), num(off.get("y"))
            col = e.get("color") or {}
            hexv = col.get("hex", "") if isinstance(col, dict) else ""
            efectos[(t, str(et), radio, dx, dy, hexv, round(float(col.get("a", 1)), 3) if isinstance(col, dict) else None)] += 1

        # 3) strokes and fills (color, alpha)
        for campo, etiqueta in (("strokePaints", "trazo"), ("fillPaints", "relleno")):
            txt = paints_a_texto(n.get(campo))
            if txt:
                trazos[(etiqueta, txt[:120], round(num(n.get("strokeWeight")) or 0, 2))] += 1

        # 4) text
        fs, lh, ls = num(n.get("fontSize")), num(n.get("lineHeight")), num(n.get("letterSpacing"))
        fn = n.get("fontName")
        if isinstance(fn, dict):
            fam = fn.get("family") or fn.get("name") or ""
        else:
            fam = str(fn or "")
        if fs:
            textos[(t, round(fs, 2), round(lh, 2) if lh else None,
                    round(ls, 4) if ls is not None else None, fam[:28], nombre[:44])] += 1

        # 5) layout spacings
        for campo in ("stackSpacing", "stackHorizontalPadding", "stackVerticalPadding",
                      "stackPaddingRight", "stackPaddingBottom"):
            v = num(n.get(campo))
            if v:
                espaciados[(campo, round(v, 2), nombre[:40])] += 1

    # ---------- dump ----------
    def volcar(nombre_fichero, titulo, contador, formateador, limite=60):
        ruta = os.path.join(destino, nombre_fichero)
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(f"# {titulo}\n")
            f.write(f"# Fuente: {origen}\n# Fecha: {date.today().isoformat()}\n")
            f.write("# Ordenado por frecuencia (cuantas veces aparece en el kit).\n")
            f.write("# 'n=' es el numero de nodos con ese valor: los de n alto son los del sistema.\n\n")
            for clave, cuenta in contador.most_common(limite):
                f.write(f"{formateador(clave)}    n={cuenta}\n")
        print(f"  -> {ruta} ({min(limite,len(contador))} of {len(contador)} values)")

    volcar("radios.txt", "RADIOS DE ESQUINA por nodo (cornerRadius)", radios,
           lambda k: f"{k[1]:>8g}  {k[0]}")

    volcar("corner-smoothing.txt", "CORNER SMOOTHING (el SQUIRCLE: 0 = circular, >0 = superelipse)",
           smoothing, lambda k: f"{k:>8g}")

    volcar("efectos.txt", "EFECTOS (sombras y difuminados)", efectos,
           lambda k: f"{k[1]:<22s} radio={str(k[2]):>6s} offset=({k[3]},{k[4]}) {k[5]} a={k[6]}  [{k[0]}]")

    volcar("trazos-rellenos.txt", "TRAZOS Y RELLENOS (color, alfa, grosor)", trazos,
           lambda k: f"grosor={k[2]:<5g} {k[0]:<8s} {k[1]}")

    volcar("textos.txt", "ESTILOS DE TEXTO REALES (fontSize / lineHeight / letterSpacing)",
           textos,
           lambda k: f"{k[1]:>5g}pt  lineHeight={str(k[2]):>5s}  letterSpacing={str(k[3]):>7s}  {k[4]:<28s} [{k[0]}] {k[5]}",
           limite=80)

    volcar("espaciados.txt", "ESPACIADOS DE LAYOUT (stack / padding)", espaciados,
           lambda k: f"{k[0]:<26s} {k[1]:>5g}  {k[2]}")

    print("\nDone.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
