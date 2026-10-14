#!/usr/bin/env python3
"""
tokens-from-figma.py — Converts Figma Variables exports into tokens TOML

INPUT
    One or more ZIPs (or folders) with `<Mode>.tokens.json` files in DTCG format,
    as Figma exports them. Each ZIP is a COLLECTION with one or more modes.

OUTPUT
    One `tokens-<collection>.toml` per ZIP, with:
      - value per mode (`claro`/`oscuro`, or the mode name as is)
      - the `{Global.Radius}` REFERENCES already resolved, noting what they pointed to
      - the provenance (Figma's `variableId`) per token

THREE THINGS A NAIVE CONVERTER DOES NOT DO
  1. RESOLVE REFERENCES. Many tokens are not values but aliases:
     `Checkboxes / Width = {Radio Button.Width}`. The chain must be followed.
  2. SUPPORT SEVERAL TYPES. Not everything is color: there are `number` (radii, sizes,
     margins) and `string`. Handling only colors throws away half the kit.
  3. NOT LOSE PRECISION. `number`s come from float32 (9.3100004196167). They are
     rounded to 4 decimals, which is plenty for points and pixels.

USAGE
    python3 tokens-from-figma.py <output/> <origin1.zip|dir> [origin2 ...]
"""

from __future__ import annotations

import json
import os
import re
import sys
import zipfile
from datetime import date

# Figma group names -> TOML keys. Those not here are normalized.
NORMALIZAR = {
    "Window Background": "window_bg",
    "Accents": "accent",
    "Accents - Vibrant": "accent_vibrant",
    "Grays": "gray",
    "Fills - Opaque": "fill",
    "Fills - Vibrant (Use Plus Lighter | Darker)": "fill_vibrant",
    "Labels": "label",
    "Labels - Vibrant (Use Plus Lighter | Darker)": "label_vibrant",
    "Miscellaneous": "misc",
    "Progress Bars": "progress",
    "Alerts": "alert",
    "Sidebar": "sidebar",
    "Tables": "table",
    "Tooltips": "tooltip",
    "Toggle (Switch)": "toggle",
    "Segmented Control": "segmented",
    "Radio Button": "radio",
    "Color Well": "color_well",
    "Combo Button": "combo_button",
    "Arrow Button": "arrow_button",
    "Global": "global",
    "Liquid Glass": "liquid_glass",
    "Large (Default)": "large_default",
    "Component Fill": "component_fill",
    "Component Stroke": "component_stroke",
    "Subcomponent Fill": "subcomponent_fill",
    "Subcomponent Stroke": "subcomponent_stroke",
    "Section Fill": "section_fill",
    "Section Stroke": "section_stroke",
}

# Collections that are iOS/iPadOS, not macOS. A warning goes in the generated header.
PLATAFORMA = {
    "Dimensions": "iPhone/iPad (iOS) — NO son metricas de macOS",
    "Dynamic Type": "iOS Dynamic Type — el Body de iOS es 17 pt; el de macOS es 13 pt",
    "Text Leading": "interlineados de iOS; utiles como PROPORCION, no como valor directo",
    "Context": "coleccion de contexto (string); no aporta valores numericos",
    "Icons": "coleccion de contexto (string); no aporta valores numericos",
}

# ---------------------------------------------------------------------------
# PROVENANCE CLASSIFIER
#
# The Figma file is MULTI-SYSTEM: it mixes Apple variables with collections from
# Material 3, from Salesforce (SDS) and from a generic color scale. Applying a
# Material 3 token to the macOS theme is a silent and serious error, so provenance is
# DERIVED FROM THE DATA, not assumed from the ZIP name.
# ---------------------------------------------------------------------------

MARCAS = {
    "Material 3": [
        "Schemes.", "Surface Tint", "On Primary", "Primary Container",
        "Static.Display Large", "Static.Headline", "Static.Title Large",
        "Static.Label Large", "Static.Body Large", "Weight Semibold",
        "Scale 01", "Scale 10", "Roboto",
    ],
    "Salesforce (SDS)": ["Utilities.Scrim", "Utilities.Blanket", "Border.Utilities"],
    "Apple macOS": [
        "Liquid Glass", "Window Background", "Accents.", "Fills - Opaque",
        "Labels.", "Global.Radius", "Toggle (Switch)", "Segmented Control",
        "Component Fill", "Section Fill",
    ],
    "Apple iOS": [
        "Sheet Top Radius", "Grabber Width", "Status Bar.Height",
        "Home Indicator", "Large (Default)", "Caption 2",
    ],
    "Escala generica": ["Pink / 100", "Blue / 100"],
}

# System the project belongs to. Everything else is marked as NOT APPLICABLE.
SISTEMA_OBJETIVO = "Apple macOS"


def clasificar(origen: str, modos: dict) -> tuple[str, str]:
    """Returns (system, markers_found) inferred from the token names."""
    nombres = set()
    for m in modos.values():
        for r in m:
            nombres.add(" / ".join(r))
            nombres.add(".".join(r))
    texto = "\n".join(sorted(nombres))

    puntuaciones = {}
    for sistema, marcas in MARCAS.items():
        golpes = [m for m in marcas if m in texto]
        if golpes:
            puntuaciones[sistema] = golpes
    if not puntuaciones:
        return "desconocido", "sin marcas reconocibles"
    sistema = max(puntuaciones, key=lambda s: len(puntuaciones[s]))
    return sistema, ", ".join(puntuaciones[sistema][:4])


def clave(nombre: str) -> str:
    if nombre in NORMALIZAR:
        return NORMALIZAR[nombre]
    s = nombre.lower().replace("+", " ").replace("|", " ").replace("/", " ")
    s = re.sub(r"[^a-z0-9]+", "_", s).strip("_")
    return s or "token"


def redondear(x) -> float:
    return round(float(x), 4) + 0.0


def hojas(obj, ruta=()):
    if isinstance(obj, dict):
        if "$value" in obj:
            yield ruta, obj
            return
        for k, v in obj.items():
            if k.startswith("$"):
                continue
            yield from hojas(v, ruta + (k,))
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            yield from hojas(v, ruta + (str(i),))


def valor_crudo(nodo):
    """Returns (type, normalized_value) from a DTCG node.

    If the value is a REFERENCE ({Global.Radius}) it is returned as is: resolving it
    is `resolver()`'s responsibility. Otherwise, a `number` with a textual value would
    blow up when converted to float.
    """
    t = nodo.get("$type", "?")
    v = nodo["$value"]
    if es_referencia(v):
        return t, v
    if t == "color" and isinstance(v, dict):
        hexv = v.get("hex")
        if not hexv:
            comps = [redondear(c) for c in v.get("components", [])]
            hexv = ("#%02X%02X%02X" % tuple(int(round(c * 255)) for c in comps[:3])
                    if len(comps) >= 3 else "?")
        return t, (hexv, redondear(v.get("alpha", 1)))
    if t == "number":
        try:
            return t, redondear(v)
        except (TypeError, ValueError):
            return t, v
    return t, v


def es_referencia(v) -> bool:
    return isinstance(v, str) and v.startswith("{") and v.endswith("}")


def resolver(valor, indice, visto=None):
    """Follows the chain of {Group.Token} references down to a real value."""
    visto = visto or set()
    if not es_referencia(valor):
        return valor, None
    destino = valor[1:-1]
    if destino in visto:
        return valor, "circular reference"
    visto.add(destino)

    nodo = None
    for k, n in indice.items():
        if ".".join(k) == destino or "/".join(k) == destino.replace(".", "/"):
            nodo = n
            break
    if nodo is None:
        return valor, f"destination not found: {destino}"
    return resolver(nodo["$value"], indice, visto)


def leer_zip(origen: str) -> dict:
    """{mode: {path: node}}"""
    modos = {}
    with zipfile.ZipFile(origen) as z:
        for n in z.namelist():
            if not n.endswith(".tokens.json"):
                continue
            modo = os.path.basename(n).replace(".tokens.json", "")
            modos[modo] = {r: t for r, t in hojas(json.loads(z.read(n)))}
    return modos


def fmt(v, tipo, ref=None) -> str:
    """Formats ONLY the value as a TOML literal.

    A reference's provenance is NOT put here: comments are not valid inside a TOML
    inline table, so they are emitted on their own separate line.
    """
    if tipo == "color" and isinstance(v, tuple):
        h, a = v
        return f'{{ hex = "{h}", alfa = {a:g} }}'
    if tipo == "number":
        return f"{v:g}"
    if isinstance(v, bool):
        return "true" if v else "false"
    return f'"{v}"'


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    solo_objetivo = "--solo-macos" in flags

    if len(args) < 2:
        print(__doc__)
        print("Options:\n  --solo-macos   skips the collections that are not from Apple macOS")
        return 2
    destino, origenes = args[0], args[1:]
    os.makedirs(destino, exist_ok=True)

    total = 0
    saltadas = []
    for origen in origenes:
        if not zipfile.is_zipfile(origen):
            print(f"WARNING: {origen} is not a ZIP, skipping")
            continue
        coleccion = os.path.basename(origen)
        if coleccion.endswith(".zip"):
            coleccion = coleccion[:-4]

        modos = leer_zip(origen)
        if not modos:
            print(f"--- {coleccion}: no .tokens.json files, skipping")
            continue

        sistema, marcas = clasificar(origen, modos)
        aplicable = sistema == SISTEMA_OBJETIVO
        etiqueta = "APPLICABLE" if aplicable else "NOT APPLICABLE"
        print(f"--- {coleccion}: {sistema} [{etiqueta}]  (markers: {marcas})")
        if not aplicable:
            saltadas.append((coleccion, sistema))
            if solo_objetivo:
                print("    -> skipped (--solo-macos)")
                continue

        indice = next(iter(modos.values()))
        m_claro = next((m for m in modos if m.lower().startswith("light")), None)
        m_oscuro = next((m for m in modos if m.lower().startswith("dark")), None)
        modos_orden = [m for m in (m_claro, m_oscuro) if m] if (m_claro and m_oscuro) else sorted(modos)

        todas = []
        for m in modos:
            for r in modos[m]:
                if r not in todas:
                    todas.append(r)

        avisos = []
        tablas: dict[str, list] = {}
        n = 0
        for ruta in todas:
            grupo = ".".join(clave(p) for p in ruta[:-1]) or clave(ruta[-1])
            nombre = clave(ruta[-1])
            nodo0 = next((modos[m][ruta] for m in modos if ruta in modos[m]), None)
            vid = (nodo0.get("$extensions", {}) or {}).get("com.figma.variableId", "?")

            valores = {}
            for m in modos_orden:
                nodo_m = modos[m].get(ruta)
                if nodo_m is None:
                    avisos.append(f"{'/'.join(ruta)}: missing in {m}")
                    continue
                tipo, v = valor_crudo(nodo_m)
                ref = None
                if es_referencia(v):
                    ref = v
                    v, err = resolver(v, indice)
                    if err:
                        avisos.append(f"{'/'.join(ruta)}: {err}")
                    # the resolved value brings its own real type, which may not be the declared one
                    if isinstance(v, bool):
                        tipo = "boolean"
                    elif isinstance(v, (int, float)):
                        tipo = "number"
                    elif isinstance(v, str):
                        tipo = "string"
                    elif isinstance(v, dict) and "hex" in v:
                        tipo, v = valor_crudo({"$type": "color", "$value": v})
                valores[m] = (tipo, v, ref)

            primero = valores.get(modos_orden[0])
            if primero and all(valores.get(m, (None, None, None))[:2] == primero[:2] for m in valores):
                tablas.setdefault(grupo, []).append((nombre, {"valor": primero}, vid))
            else:
                tablas.setdefault(grupo, []).append((nombre, dict(valores), vid))
            n += 1

        total += n
        archivo = os.path.join(destino, f"tokens-{clave(coleccion)}.toml")

        cab = [
            f"# tokens-{clave(coleccion)}.toml — GENERADO. No editar a mano.",
            "#",
            f"# Coleccion de Figma: {coleccion}",
            f"# Modos: {', '.join(sorted(modos))}",
            f"# Fecha: {date.today().isoformat()}",
            "#",
            "# Cada token lleva su variableId de Figma para poder re-verificar la cifra.",
            "# Las referencias del kit ya estan resueltas (se anota el destino original).",
        ]
        if coleccion in PLATAFORMA:
            cab += ["#", f"# ATENCION: {PLATAFORMA[coleccion]}"]
        if not aplicable:
            cab += [
                "#",
                "#" + "=" * 68,
                f"#  NO APLICABLE AL TEMA macOS: esta coleccion es de {sistema}.",
                f"#  Marcas detectadas: {marcas}",
                "#  Aplicar estos valores al escritorio de macOS daria un resultado",
                "#  incoherente. Se conserva solo como referencia.",
                "#" + "=" * 68,
            ]
        cab += ["", "[_meta]",
                f'coleccion = "{coleccion}"',
                f'sistema = "{sistema}"',
                f"aplicable_macos = {'true' if aplicable else 'false'}",
                f'modos = "{", ".join(sorted(modos))}"',
                f"tokens = {n}",
                f'fecha_export = "{date.today().isoformat()}"', ""]

        lineas = []
        for grupo in sorted(tablas):
            lineas.append(f"[{grupo}]")
            for nombre, datos, vid in sorted(tablas[grupo]):
                lineas.append(f"# {vid}")
                if "valor" in datos:
                    tipo, v, ref = datos["valor"]
                    if ref:
                        lineas.append(f"# ref: {ref} (resuelta)")
                    lineas.append(f"{nombre} = {fmt(v, tipo, ref)}")
                else:
                    partes = []
                    refs = []
                    for m in sorted(datos):
                        tipo, v, ref = datos[m]
                        partes.append(f"{clave(m)} = {fmt(v, tipo, ref)}")
                        if ref:
                            refs.append(f"{clave(m)}={ref}")
                    if refs:
                        lineas.append(f"# ref: {', '.join(refs)} (resueltas)")
                    lineas.append(f"{nombre} = {{ {', '.join(partes)} }}")
            lineas.append("")

        with open(archivo, "w", encoding="utf-8") as f:
            f.write("\n".join(cab + lineas))
        print(f"    -> {archivo} ({n} tokens, {len(avisos)} warnings)")
        for a in avisos[:4]:
            print(f"       warning: {a}")
        if len(avisos) > 4:
            print(f"       ... and {len(avisos)-4} more")

    print(f"\nTOTAL: {total} tokens")
    if saltadas:
        print("\nCOLLECTIONS THAT ARE NOT FROM macOS (kept only as a reference):")
        for c, s in saltadas:
            print(f"  - {c}: {s}")
        print("\n  To generate only the applicable ones:  --solo-macos")
    return 0


if __name__ == "__main__":
    sys.exit(main())
