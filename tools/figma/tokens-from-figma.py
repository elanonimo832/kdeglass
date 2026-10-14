#!/usr/bin/env python3
"""
tokens-from-figma.py — Convierte exports de Variables de Figma en tokens TOML

ENTRADA
    Uno o varios ZIP (o carpetas) con ficheros `<Modo>.tokens.json` en formato DTCG,
    tal como los exporta Figma. Cada ZIP es una COLECCION con uno o varios modos.

SALIDA
    Un `tokens-<coleccion>.toml` por cada ZIP, con:
      - valor por modo (`claro`/`oscuro`, o el nombre del modo tal cual)
      - las REFERENCIAS `{Global.Radius}` ya resueltas, anotando a que apuntaban
      - la procedencia (`variableId` de Figma) por token

TRES COSAS QUE UN CONVERSOR INGENUO NO HACE
  1. RESOLVER REFERENCIAS. Muchos tokens no son valores sino alias:
     `Checkboxes / Width = {Radio Button.Width}`. Hay que seguir la cadena.
  2. SOPORTAR VARIOS TIPOS. No todo es color: hay `number` (radios, tamanos, margenes)
     y `string`. Tratar solo colores tira la mitad del kit.
  3. NO PERDER PRECISION. Los `number` vienen de float32 (9.3100004196167). Se
     redondean a 4 decimales, que sobra para puntos y pixeles.

USO
    python3 tokens-from-figma.py <output/> <origen1.zip|dir> [origen2 ...]
"""

from __future__ import annotations

import json
import os
import re
import sys
import zipfile
from datetime import date

# Nombres de grupo de Figma -> claves TOML. Los que no estan aqui se normalizan.
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

# Colecciones que son de iOS/iPadOS, no de macOS. Se avisa en la cabecera generada.
PLATAFORMA = {
    "Dimensions": "iPhone/iPad (iOS) — NO son metricas de macOS",
    "Dynamic Type": "iOS Dynamic Type — el Body de iOS es 17 pt; el de macOS es 13 pt",
    "Text Leading": "interlineados de iOS; utiles como PROPORCION, no como valor directo",
    "Context": "coleccion de contexto (string); no aporta valores numericos",
    "Icons": "coleccion de contexto (string); no aporta valores numericos",
}

# ---------------------------------------------------------------------------
# CLASIFICADOR DE PROCEDENCIA
#
# El fichero de Figma es MULTI-SISTEMA: mezcla variables de Apple con colecciones de
# Material 3, de Salesforce (SDS) y de una escala de color generica. Aplicar al tema de
# macOS un token de Material 3 es un error silencioso y grave, asi que la procedencia se
# DERIVA DE LOS DATOS, no se asume por el nombre del ZIP.
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

# Sistema al que pertenece el proyecto. Todo lo demas se marca como NO APLICABLE.
SISTEMA_OBJETIVO = "Apple macOS"


def clasificar(origen: str, modos: dict) -> tuple[str, str]:
    """Devuelve (sistema, marcas_encontradas) deducido de los nombres de los tokens."""
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
    """Devuelve (tipo, valor_normalizado) desde un nodo DTCG.

    Si el valor es una REFERENCIA ({Global.Radius}) se devuelve tal cual: resolverla
    es responsabilidad de `resolver()`. Si no, un `number` con valor textual reventaria
    al convertirlo a float.
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
    """Sigue la cadena de referencias {Grupo.Token} hasta un valor real."""
    visto = visto or set()
    if not es_referencia(valor):
        return valor, None
    destino = valor[1:-1]
    if destino in visto:
        return valor, "referencia circular"
    visto.add(destino)

    nodo = None
    for k, n in indice.items():
        if ".".join(k) == destino or "/".join(k) == destino.replace(".", "/"):
            nodo = n
            break
    if nodo is None:
        return valor, f"destino no encontrado: {destino}"
    return resolver(nodo["$value"], indice, visto)


def leer_zip(origen: str) -> dict:
    """{modo: {ruta: nodo}}"""
    modos = {}
    with zipfile.ZipFile(origen) as z:
        for n in z.namelist():
            if not n.endswith(".tokens.json"):
                continue
            modo = os.path.basename(n).replace(".tokens.json", "")
            modos[modo] = {r: t for r, t in hojas(json.loads(z.read(n)))}
    return modos


def fmt(v, tipo, ref=None) -> str:
    """Formatea SOLO el valor como literal TOML.

    La procedencia de una referencia NO se pone aqui: los comentarios no son validos
    dentro de una tabla inline de TOML, asi que se emiten en su propia linea aparte.
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
        print("Opciones:\n  --solo-macos   omite las colecciones que no son de Apple macOS")
        return 2
    destino, origenes = args[0], args[1:]
    os.makedirs(destino, exist_ok=True)

    total = 0
    saltadas = []
    for origen in origenes:
        if not zipfile.is_zipfile(origen):
            print(f"AVISO: {origen} no es un ZIP, se omite")
            continue
        coleccion = os.path.basename(origen)
        if coleccion.endswith(".zip"):
            coleccion = coleccion[:-4]

        modos = leer_zip(origen)
        if not modos:
            print(f"--- {coleccion}: sin ficheros .tokens.json, se omite")
            continue

        sistema, marcas = clasificar(origen, modos)
        aplicable = sistema == SISTEMA_OBJETIVO
        etiqueta = "APLICABLE" if aplicable else "NO APLICABLE"
        print(f"--- {coleccion}: {sistema} [{etiqueta}]  (marcas: {marcas})")
        if not aplicable:
            saltadas.append((coleccion, sistema))
            if solo_objetivo:
                print("    -> omitida (--solo-macos)")
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
                    avisos.append(f"{'/'.join(ruta)}: falta en {m}")
                    continue
                tipo, v = valor_crudo(nodo_m)
                ref = None
                if es_referencia(v):
                    ref = v
                    v, err = resolver(v, indice)
                    if err:
                        avisos.append(f"{'/'.join(ruta)}: {err}")
                    # el valor resuelto trae su propio tipo real, que puede no ser el declarado
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
        print(f"    -> {archivo} ({n} tokens, {len(avisos)} avisos)")
        for a in avisos[:4]:
            print(f"       aviso: {a}")
        if len(avisos) > 4:
            print(f"       ... y {len(avisos)-4} mas")

    print(f"\nTOTAL: {total} tokens")
    if saltadas:
        print("\nCOLECCIONES QUE NO SON DE macOS (conservadas solo como referencia):")
        for c, s in saltadas:
            print(f"  - {c}: {s}")
        print("\n  Para generar solo lo aplicable:  --solo-macos")
    return 0


if __name__ == "__main__":
    sys.exit(main())
